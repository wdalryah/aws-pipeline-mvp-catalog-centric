variable "env" {
  description = "Deployment environment name (e.g. dev, prelive)."
  type        = string
}

variable "region" {
  description = "AWS region for the S3 buckets."
  type        = string
  default     = "eu-north-1"
}

variable "project" {
  description = "Project identifier used in resource naming."
  type        = string
  default     = "datalake-medallion"
}

variable "tags" {
  description = "Additional tags to merge onto every resource."
  type        = map(string)
  default     = {}
}
