output "glue_job_role_arn" {
  description = "ARN of the Glue job execution role."
  value       = aws_iam_role.glue_job_role.arn
}

output "glue_job_role_name" {
  description = "Name of the Glue job execution role."
  value       = aws_iam_role.glue_job_role.name
}

output "mwaa_execution_role_arn" {
  description = "ARN of the MWAA environment execution role."
  value       = aws_iam_role.mwaa_execution_role.arn
}

output "mwaa_execution_role_name" {
  description = "Name of the MWAA environment execution role."
  value       = aws_iam_role.mwaa_execution_role.name
}

output "athena_query_role_arn" {
  description = "ARN of the Athena query role."
  value       = aws_iam_role.athena_query_role.arn
}

output "athena_query_role_name" {
  description = "Name of the Athena query role."
  value       = aws_iam_role.athena_query_role.name
}
