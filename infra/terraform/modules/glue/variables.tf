variable "env" {
  description = "Deployment environment name (e.g. dev, prelive)."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "project" {
  description = "Project identifier used in resource naming."
  type        = string
}

variable "account_id" {
  description = "AWS account ID, used to build ARNs."
  type        = string
}

variable "data_lake_bucket_name" {
  description = "Name of the main data lake S3 bucket."
  type        = string
}

variable "data_lake_bucket_arn" {
  description = "ARN of the main data lake S3 bucket."
  type        = string
}

variable "glue_job_role_arn" {
  description = "ARN of the IAM role Glue jobs will assume."
  type        = string
}

variable "tags" {
  description = "Additional tags to merge onto every resource."
  type        = map(string)
  default     = {}
}
