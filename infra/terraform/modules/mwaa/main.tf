resource "aws_mwaa_environment" "datalake" {
  name                 = "datalake-mwaa-${var.env}"
  airflow_version      = var.airflow_version
  environment_class    = var.environment_class
  execution_role_arn   = var.mwaa_execution_role_arn
  source_bucket_arn    = var.mwaa_bucket_arn
  dag_s3_path          = "dags/"
  requirements_s3_path = "requirements.txt"

  network_configuration {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  logging_configuration {
    dag_processing_logs {
      enabled   = true
      log_level = "INFO"
    }

    scheduler_logs {
      enabled   = true
      log_level = "INFO"
    }

    task_logs {
      enabled   = true
      log_level = "INFO"
    }

    webserver_logs {
      enabled   = true
      log_level = "INFO"
    }

    worker_logs {
      enabled   = true
      log_level = "INFO"
    }
  }

  airflow_configuration_options = {
    "core.default_timezone" = "UTC"
    "core.load_examples"    = "false"
  }

  tags = var.tags
}
