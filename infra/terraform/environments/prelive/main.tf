terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Replace ACCOUNT_ID_PLACEHOLDER with your AWS account ID after running bootstrap.
  # Example: bucket = "datalake-medallion-tfstate-418638389153"
  backend "s3" {
    bucket         = "datalake-medallion-tfstate-418638389153"
    key            = "prelive/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "datalake-medallion-tflock"
    encrypt        = true
  }
}

provider "aws" {
  region  = var.region
  profile = "my-project"

  default_tags {
    tags = local.common_tags
  }
}

data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    Project     = var.project
    Environment = var.env
    ManagedBy   = "terraform"
    Region      = var.region
    Domain      = "finance"
    Org         = "acme"
  }
}

# ---------------------------------------------------------------------------
# S3 buckets
# ---------------------------------------------------------------------------
module "s3" {
  source  = "../../modules/s3"
  env     = var.env
  region  = var.region
  project = var.project
  tags    = local.common_tags
}

# ---------------------------------------------------------------------------
# IAM roles
# ---------------------------------------------------------------------------
module "iam" {
  source               = "../../modules/iam"
  env                  = var.env
  region               = var.region
  project              = var.project
  account_id           = data.aws_caller_identity.current.account_id
  data_lake_bucket_arn = module.s3.data_lake_bucket_arn
  mwaa_bucket_arn      = module.s3.mwaa_bucket_arn
  tags                 = local.common_tags
}

# ---------------------------------------------------------------------------
# Glue databases, jobs, and crawlers
# ---------------------------------------------------------------------------
module "glue" {
  source                = "../../modules/glue"
  env                   = var.env
  region                = var.region
  project               = var.project
  account_id            = data.aws_caller_identity.current.account_id
  data_lake_bucket_name = module.s3.data_lake_bucket_name
  data_lake_bucket_arn  = module.s3.data_lake_bucket_arn
  glue_job_role_arn     = module.iam.glue_job_role_arn
  tags                  = local.common_tags
}

# ---------------------------------------------------------------------------
# Athena workgroup
# ---------------------------------------------------------------------------
module "athena" {
  source                = "../../modules/athena"
  env                   = var.env
  region                = var.region
  project               = var.project
  data_lake_bucket_name = module.s3.data_lake_bucket_name
  tags                  = local.common_tags
}

# ---------------------------------------------------------------------------
# MWAA environment
# ---------------------------------------------------------------------------
module "mwaa" {
  source                  = "../../modules/mwaa"
  env                     = var.env
  region                  = var.region
  project                 = var.project
  mwaa_bucket_name        = module.s3.mwaa_bucket_name
  mwaa_bucket_arn         = module.s3.mwaa_bucket_arn
  mwaa_execution_role_arn = module.iam.mwaa_execution_role_arn
  subnet_ids              = var.subnet_ids
  security_group_ids      = var.security_group_ids
  environment_class       = "mw1.medium"
  tags                    = local.common_tags
}

# ---------------------------------------------------------------------------
# CI/CD pipeline — manual approval gate enabled for prelive
# ---------------------------------------------------------------------------
module "cicd" {
  source                = "../../modules/cicd"
  env                   = var.env
  region                = var.region
  project               = var.project
  account_id            = data.aws_caller_identity.current.account_id
  github_owner          = var.github_owner
  github_repo           = var.github_repo
  github_branch         = "prelive"
  data_lake_bucket_name = module.s3.data_lake_bucket_name
  require_approval      = true
  tags                  = local.common_tags
}
