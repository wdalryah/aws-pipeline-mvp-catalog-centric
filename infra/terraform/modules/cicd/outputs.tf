output "pipeline_name" {
  description = "Name of the CodePipeline pipeline."
  value       = aws_codepipeline.datalake.name
}

output "pipeline_arn" {
  description = "ARN of the CodePipeline pipeline."
  value       = aws_codepipeline.datalake.arn
}

output "codestar_connection_arn" {
  description = "ARN of the CodeStar connection to GitHub. Activate this in the AWS console before the first run."
  value       = aws_codestarconnections_connection.github.arn
}

output "artifacts_bucket_name" {
  description = "Name of the S3 bucket used to store pipeline artifacts."
  value       = aws_s3_bucket.artifacts.bucket
}
