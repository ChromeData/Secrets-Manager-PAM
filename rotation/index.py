"""
Rotation handler for AWS Secrets Manager.

Secrets Manager calls this function four times per rotation, once per step.
The four steps exist so a rotation can never leave you with a secret that
nothing can use:

  createSecret  - make the new password, store it as AWSPENDING
  setSecret     - push the new password into the actual system
  testSecret    - prove the new password works
  finishSecret  - promote AWSPENDING to AWSCURRENT

If any step throws, Secrets Manager stops and AWSCURRENT is untouched. The old
password still works. That property is the whole point, and it is the same
guarantee CyberArk's CPM gives you on a failed change.

This lab rotates a self-contained credential (no live database), so setSecret
and testSecret are where you would wire your own system. They are written out
in full rather than stubbed so the control flow is honest.
"""

import json
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

client = boto3.client("secretsmanager")

PASSWORD_LENGTH = int(os.environ.get("PASSWORD_LENGTH", "32"))
# Characters Secrets Manager excludes by default for broad system compatibility.
EXCLUDE_CHARACTERS = os.environ.get("EXCLUDE_CHARACTERS", "/@\"'\\")


def lambda_handler(event, context):
    arn = event["SecretId"]
    token = event["ClientRequestToken"]
    step = event["Step"]

    metadata = client.describe_secret(SecretId=arn)

    if not metadata.get("RotationEnabled"):
        raise ValueError(f"Secret {arn} is not enabled for rotation")

    versions = metadata["VersionIdsToStages"]
    if token not in versions:
        raise ValueError(f"Version {token} has no stage for secret {arn}")
    if "AWSCURRENT" in versions[token]:
        logger.info("Version %s is already AWSCURRENT. Nothing to do.", token)
        return
    if "AWSPENDING" not in versions[token]:
        raise ValueError(f"Version {token} is not AWSPENDING for secret {arn}")

    if step == "createSecret":
        create_secret(arn, token)
    elif step == "setSecret":
        set_secret(arn, token)
    elif step == "testSecret":
        test_secret(arn, token)
    elif step == "finishSecret":
        finish_secret(arn, token)
    else:
        raise ValueError(f"Unknown step: {step}")


def create_secret(arn, token):
    """Generate the new credential and park it as AWSPENDING."""
    current = json.loads(
        client.get_secret_value(SecretId=arn, VersionStage="AWSCURRENT")["SecretString"]
    )

    # If a pending version already exists, this step has run. Do not regenerate:
    # a second password here would orphan the one setSecret already pushed.
    try:
        client.get_secret_value(SecretId=arn, VersionId=token, VersionStage="AWSPENDING")
        logger.info("AWSPENDING already exists for %s. Skipping create.", token)
        return
    except client.exceptions.ResourceNotFoundException:
        pass

    new_password = client.get_random_password(
        PasswordLength=PASSWORD_LENGTH,
        ExcludeCharacters=EXCLUDE_CHARACTERS,
        RequireEachIncludedType=True,
    )["RandomPassword"]

    pending = dict(current)
    pending["password"] = new_password

    client.put_secret_value(
        SecretId=arn,
        ClientRequestToken=token,
        SecretString=json.dumps(pending),
        VersionStages=["AWSPENDING"],
    )
    logger.info("createSecret: staged new credential for %s", arn)


def set_secret(arn, token):
    """Push the pending credential into the system that consumes it.

    Wire your own target here - an RDS ALTER USER, an LDAP modify, an API call.
    The lab credential is self-contained, so there is nothing external to change
    and this is a no-op. It is left as its own function because on a real target
    this is the only step that can leave the system and the vault disagreeing.
    """
    pending = json.loads(
        client.get_secret_value(SecretId=arn, VersionId=token, VersionStage="AWSPENDING")[
            "SecretString"
        ]
    )
    logger.info(
        "setSecret: would apply new credential for user %s to the target system",
        pending.get("username", "<unset>"),
    )


def test_secret(arn, token):
    """Prove the pending credential actually works before promoting it.

    Skipping this step is how you rotate into an outage: the new password is
    promoted, the old one is retired, and nobody finds out it was never valid
    until the next connection attempt.
    """
    pending = json.loads(
        client.get_secret_value(SecretId=arn, VersionId=token, VersionStage="AWSPENDING")[
            "SecretString"
        ]
    )

    if not pending.get("password"):
        raise ValueError("testSecret: pending version has no password")
    if len(pending["password"]) < PASSWORD_LENGTH:
        raise ValueError("testSecret: pending password is shorter than required")
    if pending["password"] == pending.get("previous_password"):
        raise ValueError("testSecret: new password matches the old one")

    logger.info("testSecret: pending credential passed validation")


def finish_secret(arn, token):
    """Promote AWSPENDING to AWSCURRENT. This is the atomic cutover."""
    metadata = client.describe_secret(SecretId=arn)

    current_version = None
    for version, stages in metadata["VersionIdsToStages"].items():
        if "AWSCURRENT" in stages:
            if version == token:
                logger.info("finishSecret: %s is already current", version)
                return
            current_version = version
            break

    client.update_secret_version_stage(
        SecretId=arn,
        VersionStage="AWSCURRENT",
        MoveToVersionId=token,
        RemoveFromVersionId=current_version,
    )
    logger.info("finishSecret: promoted %s to AWSCURRENT for %s", token, arn)
