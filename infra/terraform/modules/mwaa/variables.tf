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

variable "mwaa_bucket_name" {
  description = "Name of the S3 bucket used by MWAA for DAGs and requirements."
  type        = string
}

variable "mwaa_bucket_arn" {
  description = "ARN of the S3 bucket used by MWAA for DAGs and requirements."
  type        = string
}

variable "mwaa_execution_role_arn" {
  description = "ARN of the IAM role that MWAA will assume."
  type        = string
}

variable "subnet_ids" {
  description = "List of private subnet IDs for the MWAA environment (minimum 2)."
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs to attach to the MWAA environment."
  type        = list(string)
}

variable "environment_class" {
  description = "MWAA environment class (mw1.small, mw1.medium, mw1.large)."
  type        = string
  default     = "mw1.small"
}

variable "airflow_version" {
  description = "Apache Airflow version for the MWAA environment."
  type        = string
  default     = "2.8.1"
}

variable "tags" {
  description = "Additional tags to merge onto every resource."
  type        = map(string)
  default     = {}
}
