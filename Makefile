.PHONY: help init fmt validate plan apply rotate-now watch-rotation audit read-as-consumer prove-denied destroy

TF      := terraform -chdir=terraform
SECRET  := $(shell $(TF) output -raw secret_name 2>/dev/null)
FUNC    := $(shell $(TF) output -raw rotation_function_name 2>/dev/null)
LOGS    := $(shell $(TF) output -raw trail_log_group 2>/dev/null)

help:
	@echo "init             install providers and modules"
	@echo "validate         syntax + provider check (no AWS calls)"
	@echo "plan             show what would be created"
	@echo "apply            build the lab"
	@echo "rotate-now       force a rotation and wait for it to finish"
	@echo "watch-rotation   tail the rotation function's logs"
	@echo "audit            who read the secret, from CloudTrail data events"
	@echo "read-as-consumer read the secret as the app role (should succeed)"
	@echo "prove-denied     read as your own identity (should FAIL - that is the test)"
	@echo "destroy          tear everything down"

init:
	$(TF) init

fmt:
	$(TF) fmt -recursive

validate: fmt
	$(TF) validate

plan: init
	$(TF) plan

apply: init
	$(TF) apply -auto-approve

# ---------------------------------------------------------------------------
# Rotation
# ---------------------------------------------------------------------------
rotate-now:
	@echo "==> forcing rotation of $(SECRET)"
	aws secretsmanager rotate-secret --secret-id $(SECRET) --no-cli-pager
	@echo "==> waiting for AWSPENDING to clear (rotation complete)"
	@for i in $$(seq 1 30); do \
	  pending=$$(aws secretsmanager describe-secret --secret-id $(SECRET) \
	    --query 'VersionIdsToStages.*[?@==`AWSPENDING`]' --output text); \
	  if [ -z "$$pending" ]; then echo "    rotation finished"; exit 0; fi; \
	  sleep 5; \
	done; \
	echo "    still pending after 150s - check 'make watch-rotation'"; exit 1

watch-rotation:
	aws logs tail /aws/lambda/$(FUNC) --follow --since 10m

# ---------------------------------------------------------------------------
# The two tests that prove the access model works
# ---------------------------------------------------------------------------
read-as-consumer:
	@echo "==> assuming the consumer role and reading the secret"
	@creds=$$(aws sts assume-role \
	  --role-arn $$($(TF) output -raw consumer_role_arn) \
	  --role-session-name lab05-read --output json); \
	AWS_ACCESS_KEY_ID=$$(echo $$creds | jq -r .Credentials.AccessKeyId) \
	AWS_SECRET_ACCESS_KEY=$$(echo $$creds | jq -r .Credentials.SecretAccessKey) \
	AWS_SESSION_TOKEN=$$(echo $$creds | jq -r .Credentials.SessionToken) \
	aws secretsmanager get-secret-value --secret-id $(SECRET) \
	  --query 'SecretString' --output text | jq '.username, .engine'

prove-denied:
	@echo "==> reading as your own identity - this SHOULD be denied by the resource policy"
	@if aws secretsmanager get-secret-value --secret-id $(SECRET) >/dev/null 2>&1; then \
	  echo "    UNEXPECTED: the read succeeded. The deny statement is not working."; exit 1; \
	else \
	  echo "    denied, as designed. Identity policy allowed it; resource policy refused."; \
	fi

# ---------------------------------------------------------------------------
# Audit
# ---------------------------------------------------------------------------
audit:
	@echo "==> GetSecretValue events in the last hour"
	aws logs filter-log-events \
	  --log-group-name $(LOGS) \
	  --start-time $$(( ($$(date +%s) - 3600) * 1000 )) \
	  --filter-pattern '{ $$.eventName = "GetSecretValue" }' \
	  --query 'events[].message' --output text \
	| jq -r '[.eventTime, .userIdentity.arn, .sourceIPAddress] | @tsv' 2>/dev/null \
	|| echo "    no reads recorded yet - run 'make read-as-consumer' first"

destroy:
	$(TF) destroy -auto-approve
