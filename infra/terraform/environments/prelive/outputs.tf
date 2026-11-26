output "data_lake_bucket_name" {
  description = "Name of the main data lake S3 bucket."
  value       = module.s3.data_lake_bucket_name
}

output "mwaa_bucket_name" {
  description = "Name of the MWAA S3 bucket."
  value       = module.s3.mwaa_bucket_name
}

output "glue_job_role_arn" {
  description = "ARN of the Glue job execution role."
  value       = module.iam.glue_job_role_arn
}

output "mwaa_execution_role_arn" {
  description = "ARN of the MWAA execution role."
  value       = module.iam.mwaa_execution_role_arn
}

output "athena_query_role_arn" {
  description = "ARN of the Athena query role."
  value       = module.iam.athena_query_role_arn
}

output "bronze_db_name" {
  description = "Name of the bronze Glue catalog database."
  value       = module.glue.bronze_db_name
}

output "gold_db_name" {
  description = "Name of the gold Glue catalog database."
  value       = module.glue.gold_db_name
}

output "athena_workgroup_name" {
  description = "Name of the Athena workgroup."
  value       = module.athena.workgroup_name
}

output "mwaa_environment_name" {
  description = "Name of the MWAA environment."
  value       = module.mwaa.mwaa_environment_name
}

output "pipeline_name" {
  description = "Name of the CodePipeline CI/CD pipeline."
  value       = module.cicd.pipeline_name
}
