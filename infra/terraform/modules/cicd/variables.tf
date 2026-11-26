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
  description = "AWS account ID."
  type        = string
}

variable "github_owner" {
  description = "GitHub organization or user that owns the repository."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without owner prefix)."
  type        = string
}

variable "github_branch" {
  description = "GitHub branch to trigger the pipeline on."
  type        = string
}

variable "data_lake_bucket_name" {
  description = "Name of the data lake bucket (used for naming the artifacts bucket)."
  type        = string
}

variable "require_approval" {
  description = "When true, insert a manual approval stage between TF Plan and TF Apply."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional tags to merge onto every resource."
  type        = map(string)
  default     = {}
}
