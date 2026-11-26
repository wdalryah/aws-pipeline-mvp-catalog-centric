resource "aws_athena_workgroup" "datalake" {
  name        = "datalake-${var.env}"
  description = "Athena workgroup for the ${var.env} data lakehouse environment."

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${var.data_lake_bucket_name}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }
  }

  tags = var.tags
}
