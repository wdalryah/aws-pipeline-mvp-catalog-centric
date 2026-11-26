output "data_lake_bucket_id" {
  description = "ID (name) of the main data lake S3 bucket."
  value       = aws_s3_bucket.data_lake.id
}

output "data_lake_bucket_arn" {
  description = "ARN of the main data lake S3 bucket."
  value       = aws_s3_bucket.data_lake.arn
}

output "data_lake_bucket_name" {
  description = "Name of the main data lake S3 bucket (same as ID)."
  value       = aws_s3_bucket.data_lake.bucket
}

output "mwaa_bucket_id" {
  description = "ID (name) of the MWAA S3 bucket."
  value       = aws_s3_bucket.mwaa.id
}

output "mwaa_bucket_arn" {
  description = "ARN of the MWAA S3 bucket."
  value       = aws_s3_bucket.mwaa.arn
}

output "mwaa_bucket_name" {
  description = "Name of the MWAA S3 bucket (same as ID)."
  value       = aws_s3_bucket.mwaa.bucket
}
