.PHONY: help init plan apply rotate-now audit destroy
.DEFAULT_GOAL := help
TF := terraform -chdir=terraform

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

init: ## terraform init
	$(TF) init -upgrade

plan: ## terraform plan
	$(TF) plan

apply: ## terraform apply
	$(TF) apply

rotate-now: ## Force an immediate rotation and watch it
	aws secretsmanager rotate-secret --secret-id lab05/database/app
	@echo "Check CloudTrail / the secret's version stages."

audit: ## Pull recent GetSecretValue events from CloudTrail
	aws cloudtrail lookup-events \
		--lookup-attributes AttributeKey=EventName,AttributeValue=GetSecretValue \
		--max-results 20 --query 'Events[].{Time:EventTime,User:Username}' --output table

destroy: ## terraform destroy
	$(TF) destroy
