locals {
  raw_to_bronze_tables = ["customers", "orders", "products"]
}

# ---------------------------------------------------------------------------
# Glue Data Catalog Databases
# ---------------------------------------------------------------------------
resource "aws_glue_catalog_database" "bronze" {
  name        = "bronze_db_${var.env}"
  description = "Bronze layer database for ${var.env} - cleaned raw data as Parquet."

  location_uri = "s3://${var.data_lake_bucket_name}/bronze/"
}

resource "aws_glue_catalog_database" "gold" {
  name        = "gold_db_${var.env}"
  description = "Gold layer database for ${var.env} - curated semantic tables."

  location_uri = "s3://${var.data_lake_bucket_name}/gold/"
}

# ---------------------------------------------------------------------------
# Glue Jobs: raw → bronze (one per table)
# ---------------------------------------------------------------------------
resource "aws_glue_job" "raw_to_bronze" {
  for_each = toset(local.raw_to_bronze_tables)

  name         = "raw_to_bronze_${each.key}_${var.env}"
  role_arn     = var.glue_job_role_arn
  glue_version = "4.0"
  worker_type  = "G.1X"
  timeout      = 60

  number_of_workers = 2

  command {
    name            = "glueetl"
    script_location = "s3://${var.data_lake_bucket_name}/scripts/glue/jobs/raw_to_bronze/raw_to_bronze.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--enable-job-insights"              = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"                   = "true"
    "--TempDir"                          = "s3://${var.data_lake_bucket_name}/glue-temp/"
    "--env"                              = var.env
    "--region"                           = var.region
    "--source_path"                      = "s3://${var.data_lake_bucket_name}/raw/landing/${each.key}/"
    "--target_path"                      = "s3://${var.data_lake_bucket_name}/bronze/${each.key}/"
    "--table_name"                       = each.key
  }

  execution_property {
    max_concurrent_runs = 1
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Glue Job: bronze → gold (Athena CTAS driver)
# ---------------------------------------------------------------------------
resource "aws_glue_job" "bronze_to_gold" {
  name         = "bronze_to_gold_semantic_orders_${var.env}"
  role_arn     = var.glue_job_role_arn
  glue_version = "4.0"
  worker_type  = "G.1X"
  timeout      = 60

  number_of_workers = 2

  command {
    name            = "glueetl"
    script_location = "s3://${var.data_lake_bucket_name}/scripts/glue/jobs/bronze_to_gold/bronze_to_gold.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--enable-job-insights"              = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"                   = "true"
    "--TempDir"                          = "s3://${var.data_lake_bucket_name}/glue-temp/"
    "--env"                              = var.env
    "--region"                           = var.region
    "--source_db"                        = "bronze_db_${var.env}"
    "--target_path"                      = "s3://${var.data_lake_bucket_name}/gold/semantic_orders_summary/"
    "--workgroup"                        = "datalake-${var.env}"
  }

  execution_property {
    max_concurrent_runs = 1
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Glue Crawlers
# ---------------------------------------------------------------------------
resource "aws_glue_crawler" "bronze" {
  name          = "bronze_crawler_${var.env}"
  database_name = aws_glue_catalog_database.bronze.name
  role          = var.glue_job_role_arn
  schedule      = "cron(0 3 1,15 * ? *)"
  description   = "Crawls the bronze S3 layer and updates the Glue catalog."

  s3_target {
    path = "s3://${var.data_lake_bucket_name}/bronze/"
  }

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
  })

  tags = var.tags
}

resource "aws_glue_crawler" "gold" {
  name          = "gold_crawler_${var.env}"
  database_name = aws_glue_catalog_database.gold.name
  role          = var.glue_job_role_arn
  schedule      = "cron(0 4 1,15 * ? *)"
  description   = "Crawls the gold S3 layer and updates the Glue catalog."

  s3_target {
    path = "s3://${var.data_lake_bucket_name}/gold/"
  }

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
    }
  })

  tags = var.tags
}
