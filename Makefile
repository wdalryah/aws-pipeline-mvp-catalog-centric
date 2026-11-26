# datalake-medallion Makefile
# Org: acme  |  Domain: finance  |  Env: prelive  |  Region: eu-north-1
#
# Usage:
#   make bootstrap          — one-time backend setup
#   make plan               — terraform plan
#   make apply              — terraform apply (requires CONFIRM=yes)
#   make destroy            — terraform destroy (requires CONFIRM=yes)
#   make upload-scripts     — sync processing code to S3
#   make upload-dags        — sync workflow/dags to MWAA bucket
#   make fmt                — format all Terraform
#   make validate           — validate Terraform config

SHELL   := /bin/bash
PROJECT := datalake-medallion
REGION  := eu-north-1
PROFILE := my-project

TF_ENV     := infra/terraform/environments/prelive
TF_BACKEND := infra/terraform/backend

# Resolve bucket names from Terraform outputs (falls back to convention if not yet applied)
DATA_LAKE_BUCKET := $(shell cd $(TF_ENV) && terraform output -raw data_lake_bucket_name 2>/dev/null || echo "datalake-medallion-prelive-$(REGION)")
MWAA_BUCKET      := $(shell cd $(TF_ENV) && terraform output -raw mwaa_bucket_name      2>/dev/null || echo "datalake-medallion-mwaa-prelive")

.PHONY: help bootstrap fmt validate plan apply destroy \
        upload-scripts upload-dags

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-22s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# Backend bootstrap (run once before any environment apply)
# ---------------------------------------------------------------------------
bootstrap: ## Init and apply Terraform backend (run once)
	cd $(TF_BACKEND) && terraform init && terraform apply -auto-approve

# ---------------------------------------------------------------------------
# Terraform
# ---------------------------------------------------------------------------
fmt: ## Format all Terraform code recursively
	terraform fmt -recursive infra/terraform/

validate: ## Validate Terraform configuration
	cd $(TF_ENV) && terraform init -backend=false && terraform validate

plan: ## Terraform plan for prelive
	cd $(TF_ENV) && terraform init && terraform plan -out=tfplan

apply: ## Terraform apply for prelive (requires CONFIRM=yes)
	@[ "$(CONFIRM)" = "yes" ] || (echo "ERROR: Set CONFIRM=yes to apply  e.g. make apply CONFIRM=yes"; exit 1)
	cd $(TF_ENV) && terraform init && terraform apply tfplan

destroy: ## Destroy prelive environment (requires CONFIRM=yes)
	@[ "$(CONFIRM)" = "yes" ] || (echo "ERROR: Set CONFIRM=yes to destroy  e.g. make destroy CONFIRM=yes"; exit 1)
	cd $(TF_ENV) && terraform destroy -auto-approve

# ---------------------------------------------------------------------------
# Artifact uploads
# ---------------------------------------------------------------------------
upload-scripts: ## Sync processing code (bronze + gold) to data lake scripts prefix
	aws s3 sync processing/common_code/ \
		s3://$(DATA_LAKE_BUCKET)/scripts/processing/ \
		--exclude "*.pyc" --exclude "__pycache__/*" \
		--region $(REGION) --profile $(PROFILE)
	@echo "Scripts uploaded to s3://$(DATA_LAKE_BUCKET)/scripts/processing/"

upload-dags: ## Sync Airflow DAGs and requirements to MWAA bucket
	aws s3 sync workflow/dags/ \
		s3://$(MWAA_BUCKET)/dags/ \
		--region $(REGION) --profile $(PROFILE)
	aws s3 cp workflow/requirements.txt \
		s3://$(MWAA_BUCKET)/requirements.txt \
		--region $(REGION) --profile $(PROFILE)
	@echo "DAGs uploaded to s3://$(MWAA_BUCKET)/dags/"
