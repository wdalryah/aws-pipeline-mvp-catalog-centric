"""
raw_to_bronze.py - AWS Glue PySpark job for raw to bronze layer transformation.
Reads CSV from raw/landing, adds audit columns, writes Parquet to bronze layer.
"""
import sys
import hashlib
from typing import List
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.types import BooleanType
import logging

# Configure logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

# Table natural key mapping
NATURAL_KEYS: dict = {
    "customers": ["customer_id"],
    "orders": ["order_id"],
    "products": ["product_id"],
}


def get_job_args() -> dict:
    """Parse and return Glue job arguments."""
    args = getResolvedOptions(
        sys.argv,
        [
            "JOB_NAME",
            "JOB_RUN_ID",
            "env",
            "region",
            "source_path",
            "target_path",
            "table_name",
        ],
    )
    return args


def read_csv(glue_context: GlueContext, source_path: str) -> DataFrame:
    """Read CSV file from S3 with header and schema inference."""
    logger.info(f"Reading CSV from: {source_path}")
    spark = glue_context.spark_session
    df = (
        spark.read.option("header", "true")
        .option("inferSchema", "true")
        .csv(source_path)
    )
    logger.info(f"Read {df.count()} records from {source_path}")
    return df


def add_audit_columns(
    df: DataFrame,
    table_name: str,
    env: str,
    region: str,
    job_run_id: str,
) -> DataFrame:
    """
    Add all required audit columns to the DataFrame.

    Audit columns added:
    - pk_surrogate: SHA-256 hash of natural key columns
    - source_system: literal string identifying the system
    - source_file: input file name from S3
    - ingestion_timestamp: current timestamp at ingestion
    - ingestion_date: current date (partition column)
    - env: environment name (dev/prelive)
    - region: AWS region
    - job_run_id: Glue job run ID
    - is_deleted: soft delete flag, default False
    - record_hash: SHA-256 hash of all original columns for change detection
    """
    natural_keys = NATURAL_KEYS.get(table_name, [df.columns[0]])
    original_columns: List[str] = df.columns

    # record_hash over all original columns
    record_hash_expr = F.sha2(
        F.concat_ws("|", *[F.col(c).cast("string") for c in original_columns]), 256
    )

    # pk_surrogate over natural key columns
    pk_surrogate_expr = F.sha2(
        F.concat_ws("|", *[F.col(c).cast("string") for c in natural_keys]), 256
    )

    df_with_audit = (
        df.withColumn("pk_surrogate", pk_surrogate_expr)
        .withColumn("source_system", F.lit("datalake-medallion"))
        .withColumn("source_file", F.input_file_name())
        .withColumn("ingestion_timestamp", F.current_timestamp())
        .withColumn("ingestion_date", F.current_date())
        .withColumn("env", F.lit(env))
        .withColumn("region", F.lit(region))
        .withColumn("job_run_id", F.lit(job_run_id))
        .withColumn("is_deleted", F.lit(False).cast(BooleanType()))
        .withColumn("record_hash", record_hash_expr)
    )

    logger.info(f"Added audit columns to {table_name}. Final schema: {df_with_audit.columns}")
    return df_with_audit


def write_to_bronze(
    glue_context: GlueContext,
    df: DataFrame,
    target_path: str,
    database: str,
    table_name: str,
) -> None:
    """
    Write DataFrame as Parquet to bronze S3 path, partitioned by ingestion_date.
    Registers table in Glue Data Catalog.
    """
    logger.info(f"Writing {df.count()} records to bronze: {target_path}")

    dynamic_frame = DynamicFrame.fromDF(df, glue_context, table_name)

    sink = glue_context.getSink(
        connection_type="s3",
        path=target_path,
        enableUpdateCatalog=True,
        updateBehavior="UPDATE_IN_DATABASE",
        partitionKeys=["ingestion_date"],
    )
    sink.setFormat("glueparquet", compression="snappy")
    sink.setCatalogInfo(catalogDatabase=database, catalogTableName=table_name)
    sink.writeFrame(dynamic_frame)
    logger.info(
        f"Successfully wrote {table_name} to {target_path} "
        f"and registered in catalog {database}"
    )


def main() -> None:
    """Main entry point for the Glue job."""
    args = get_job_args()

    sc = SparkContext()
    glue_context = GlueContext(sc)
    spark = glue_context.spark_session
    job = Job(glue_context)
    job.init(args["JOB_NAME"], args)

    env = args["env"]
    region = args["region"]
    source_path = args["source_path"]
    target_path = args["target_path"]
    table_name = args["table_name"]
    job_run_id = args["JOB_RUN_ID"]
    database = f"bronze_db_{env}"

    try:
        logger.info(
            f"Starting raw_to_bronze for table={table_name}, env={env}, region={region}"
        )

        df = read_csv(glue_context, source_path)
        df_with_audit = add_audit_columns(df, table_name, env, region, job_run_id)
        write_to_bronze(glue_context, df_with_audit, target_path, database, table_name)

        logger.info(f"raw_to_bronze completed successfully for table={table_name}")
    except Exception as e:
        logger.error(
            f"raw_to_bronze FAILED for table={table_name}: {str(e)}", exc_info=True
        )
        raise
    finally:
        job.commit()


if __name__ == "__main__":
    main()
