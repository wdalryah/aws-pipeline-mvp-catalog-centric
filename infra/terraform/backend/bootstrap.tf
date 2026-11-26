# bootstrap.tf
# ---------------------------------------------------------------------------
# This file must be applied ONCE before any environment Terraform configuration.
# It creates the shared S3 bucket for Terraform remote state and the DynamoDB
# table used for state locking. Run:
#
#   cd infra/terraform/backend
#   terraform init
#   terraform apply
#
# After apply, copy the output bucket name into each environment's backend block.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-north-1"
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# S3 bucket for Terraform remote state
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "tfstate" {
  bucket = "datalake-medallion-tfstate-${data.aws_caller_identity.current.account_id}"

  tags = {
    Project   = "datalake-medallion"
    ManagedBy = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# DynamoDB table for Terraform state locking
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "tflock" {
  name         = "datalake-medallion-tflock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project   = "datalake-medallion"
    ManagedBy = "terraform"
  }
}
