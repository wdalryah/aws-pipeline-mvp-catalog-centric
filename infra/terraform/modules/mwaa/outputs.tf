output "mwaa_environment_name" {
  description = "Name of the MWAA environment."
  value       = aws_mwaa_environment.datalake.name
}

output "mwaa_webserver_url" {
  description = "URL of the MWAA Airflow web UI."
  value       = aws_mwaa_environment.datalake.webserver_url
}

output "mwaa_arn" {
  description = "ARN of the MWAA environment."
  value       = aws_mwaa_environment.datalake.arn
}
