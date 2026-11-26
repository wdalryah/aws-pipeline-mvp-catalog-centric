variable "env" {
  description = "Deployment environment. Single environment pointing at the connected AWS account."
  type        = string
  default     = "prelive"
}

variable "region" {
  description = "AWS region for all resources. Matches the region of the connected account."
  type        = string
  default     = "eu-north-1"
}

variable "project" {
  description = "Project identifier used in resource naming."
  type        = string
  default     = "datalake-medallion"
}

variable "github_owner" {
  description = "GitHub organization name (e.g. acme)."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name without the owner prefix."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the MWAA environment. Must be in eu-north-1."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs to attach to the MWAA environment."
  type        = list(string)
}

variable "tags" {
  description = "Additional tags merged onto all resources."
  type        = map(string)
  default     = {}
}
