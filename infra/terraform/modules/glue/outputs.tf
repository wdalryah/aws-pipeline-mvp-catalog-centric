output "bronze_db_name" {
  description = "Name of the bronze Glue catalog database."
  value       = aws_glue_catalog_database.bronze.name
}

output "gold_db_name" {
  description = "Name of the gold Glue catalog database."
  value       = aws_glue_catalog_database.gold.name
}

output "raw_to_bronze_customers_job_name" {
  description = "Name of the raw→bronze Glue job for customers."
  value       = aws_glue_job.raw_to_bronze["customers"].name
}

output "raw_to_bronze_orders_job_name" {
  description = "Name of the raw→bronze Glue job for orders."
  value       = aws_glue_job.raw_to_bronze["orders"].name
}

output "raw_to_bronze_products_job_name" {
  description = "Name of the raw→bronze Glue job for products."
  value       = aws_glue_job.raw_to_bronze["products"].name
}

output "bronze_to_gold_job_name" {
  description = "Name of the bronze→gold semantic orders Glue job."
  value       = aws_glue_job.bronze_to_gold.name
}

output "bronze_crawler_name" {
  description = "Name of the bronze layer Glue crawler."
  value       = aws_glue_crawler.bronze.name
}

output "gold_crawler_name" {
  description = "Name of the gold layer Glue crawler."
  value       = aws_glue_crawler.gold.name
}
