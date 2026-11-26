"""
medallion_pipeline.py - Airflow DAG for the acme/finance datalake pipeline.

Domain : finance (customers, orders, products)
Org    : acme
Env    : prelive (single deployed environment)
Region : eu-north-1

Schedule: 1st and 15th of each month at 02:00 UTC.
Flow   : raw/landing → bronze (3 parallel Glue jobs) → gold (Athena CTAS)
"""
from __future__ import annotations

import logging
from datetime import datetime, timedelta
from typing import Any, Dict

from airflow import DAG
from airflow.models import Variable
from airflow.providers.amazon.aws.operators.glue import GlueJobOperator
from airflow.providers.amazon.aws.operators.athena import AthenaOperator

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Runtime configuration — read from Airflow Variables so values can be
# updated without redeploying the DAG file.
# ---------------------------------------------------------------------------
ENV: str    = Variable.get("env",           default_var="prelive")
REGION: str = Variable.get("aws_region",    default_var="eu-north-1")
DATA_LAKE_BUCKET: str = Variable.get(
    "data_lake_bucket",
    default_var=f"datalake-medallion-{ENV}-{REGION}",
)
ATHENA_WORKGROUP: str = Variable.get(
    "athena_workgroup",
    default_var=f"datalake-{ENV}",
)
ATHENA_OUTPUT: str = f"s3://{DATA_LAKE_BUCKET}/athena-results/"

# ---------------------------------------------------------------------------
# Default task arguments
# ---------------------------------------------------------------------------
DEFAULT_ARGS: Dict[str, Any] = {
    "owner": "acme-data-engineering",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "execution_timeout": timedelta(hours=2),
}

# ---------------------------------------------------------------------------
# Gold layer SQL — INSERT INTO the pre-created partitioned table.
# The CTAS table is created by Terraform (Glue module) on first deploy;
# subsequent runs INSERT into the existing partition.
# ---------------------------------------------------------------------------
GOLD_SQL = f"""
INSERT INTO gold_db_{ENV}.semantic_orders_summary
SELECT
    o.order_id,
    o.order_date,
    c.customer_id,
    c.name         AS customer_name,
    c.email        AS customer_email,
    c.country      AS customer_country,
    p.product_id,
    p.product_name,
    p.category     AS product_category,
    CAST(o.amount AS DOUBLE)                            AS order_amount,
    CAST(p.price  AS DOUBLE)                            AS list_price,
    CAST(o.amount AS DOUBLE) - CAST(p.price AS DOUBLE)  AS discount_amount,
    o.pk_surrogate,
    o.source_system,
    o.source_file,
    o.ingestion_timestamp,
    o.env,
    o.region,
    o.job_run_id,
    o.is_deleted,
    o.record_hash,
    o.ingestion_date
FROM  bronze_db_{ENV}.orders    o
INNER JOIN bronze_db_{ENV}.customers c ON o.customer_id = c.customer_id
INNER JOIN bronze_db_{ENV}.products  p ON o.product     = p.product_name
WHERE o.is_deleted = FALSE
  AND c.is_deleted = FALSE
  AND p.is_deleted = FALSE
"""

# ---------------------------------------------------------------------------
# DAG
# ---------------------------------------------------------------------------
with DAG(
    dag_id="acme_finance_medallion_pipeline",
    description="acme/finance: raw/landing → bronze → gold  |  prelive / eu-north-1",
    schedule_interval="0 2 1,15 * *",
    start_date=datetime(2024, 1, 1),
    catchup=False,
    max_active_runs=1,
    default_args=DEFAULT_ARGS,
    tags=["acme", "finance", "datalake", "medallion", ENV],
) as dag:

    # ------------------------------------------------------------------
    # Bronze layer — 3 Glue jobs run in parallel (one per finance table)
    # ------------------------------------------------------------------
    bronze_customers = GlueJobOperator(
        task_id="bronze_customers",
        job_name=f"raw_to_bronze_customers_{ENV}",
        script_args={
            "--env":         ENV,
            "--region":      REGION,
            "--source_path": f"s3://{DATA_LAKE_BUCKET}/raw/landing/customers/",
            "--target_path": f"s3://{DATA_LAKE_BUCKET}/bronze/customers/",
            "--table_name":  "customers",
        },
        aws_conn_id="aws_default",
        region_name=REGION,
        wait_for_completion=True,
    )

    bronze_orders = GlueJobOperator(
        task_id="bronze_orders",
        job_name=f"raw_to_bronze_orders_{ENV}",
        script_args={
            "--env":         ENV,
            "--region":      REGION,
            "--source_path": f"s3://{DATA_LAKE_BUCKET}/raw/landing/orders/",
            "--target_path": f"s3://{DATA_LAKE_BUCKET}/bronze/orders/",
            "--table_name":  "orders",
        },
        aws_conn_id="aws_default",
        region_name=REGION,
        wait_for_completion=True,
    )

    bronze_products = GlueJobOperator(
        task_id="bronze_products",
        job_name=f"raw_to_bronze_products_{ENV}",
        script_args={
            "--env":         ENV,
            "--region":      REGION,
            "--source_path": f"s3://{DATA_LAKE_BUCKET}/raw/landing/products/",
            "--target_path": f"s3://{DATA_LAKE_BUCKET}/bronze/products/",
            "--table_name":  "products",
        },
        aws_conn_id="aws_default",
        region_name=REGION,
        wait_for_completion=True,
    )

    # ------------------------------------------------------------------
    # Gold layer — Athena CTAS after all 3 bronze jobs succeed
    # ------------------------------------------------------------------
    gold_semantic = AthenaOperator(
        task_id="gold_semantic_orders",
        query=GOLD_SQL,
        database=f"gold_db_{ENV}",
        output_location=ATHENA_OUTPUT,
        workgroup=ATHENA_WORKGROUP,
        aws_conn_id="aws_default",
        region_name=REGION,
    )

    # ------------------------------------------------------------------
    # Dependencies
    # ------------------------------------------------------------------
    [bronze_customers, bronze_orders, bronze_products] >> gold_semantic
