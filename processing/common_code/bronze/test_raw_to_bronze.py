"""
test_raw_to_bronze.py - Unit tests for raw_to_bronze PySpark transformations.
Tests run without a real Glue/AWS environment using local PySpark.
"""
import pytest
from unittest.mock import MagicMock, patch
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import (
    StructType, StructField, StringType, DoubleType, BooleanType
)
import sys
import os

# Allow importing the job module
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../jobs/raw_to_bronze"))


@pytest.fixture(scope="session")
def spark():
    """Create a local SparkSession for testing."""
    return (
        SparkSession.builder
        .master("local[1]")
        .appName("test_raw_to_bronze")
        .config("spark.sql.shuffle.partitions", "1")
        .getOrCreate()
    )


@pytest.fixture
def sample_customers_df(spark):
    """Sample customers DataFrame matching CSV schema."""
    data = [
        ("C001", "Alice Smith", "alice@example.com", "US"),
        ("C002", "Bob Jones",   "bob@example.com",   "GB"),
        ("C003", "Clara Diaz",  "clara@example.com", "ES"),
    ]
    schema = StructType([
        StructField("customer_id", StringType(), True),
        StructField("name",        StringType(), True),
        StructField("email",       StringType(), True),
        StructField("country",     StringType(), True),
    ])
    return spark.createDataFrame(data, schema)


@pytest.fixture
def sample_orders_df(spark):
    """Sample orders DataFrame matching CSV schema."""
    data = [
        ("O001", "C001", "Widget A", 99.99,  "2024-01-15"),
        ("O002", "C002", "Widget B", 149.50, "2024-01-16"),
    ]
    schema = StructType([
        StructField("order_id",    StringType(), True),
        StructField("customer_id", StringType(), True),
        StructField("product",     StringType(), True),
        StructField("amount",      DoubleType(), True),
        StructField("order_date",  StringType(), True),
    ])
    return spark.createDataFrame(data, schema)


class TestAddAuditColumns:
    """Tests for the add_audit_columns function."""

    def test_audit_columns_added(self, spark, sample_customers_df):
        """All 10 audit columns must be present after transformation."""
        with patch.dict("sys.modules", {
            "awsglue":               MagicMock(),
            "awsglue.transforms":    MagicMock(),
            "awsglue.utils":         MagicMock(),
            "awsglue.context":       MagicMock(),
            "awsglue.job":           MagicMock(),
            "awsglue.dynamicframe":  MagicMock(),
        }):
            from raw_to_bronze import add_audit_columns

            result = add_audit_columns(
                sample_customers_df,
                table_name="customers",
                env="dev",
                region="eu-north-1",
                job_run_id="jr_test_001",
            )

            expected_audit_cols = [
                "pk_surrogate",
                "source_system",
                "source_file",
                "ingestion_timestamp",
                "ingestion_date",
                "env",
                "region",
                "job_run_id",
                "is_deleted",
                "record_hash",
            ]
            for col in expected_audit_cols:
                assert col in result.columns, f"Missing audit column: {col}"

    def test_source_system_literal(self, spark, sample_customers_df):
        """source_system must equal 'datalake-medallion'."""
        with patch.dict("sys.modules", {
            "awsglue":               MagicMock(),
            "awsglue.transforms":    MagicMock(),
            "awsglue.utils":         MagicMock(),
            "awsglue.context":       MagicMock(),
            "awsglue.job":           MagicMock(),
            "awsglue.dynamicframe":  MagicMock(),
        }):
            from raw_to_bronze import add_audit_columns

            result = add_audit_columns(
                sample_customers_df, "customers", "dev", "eu-north-1", "jr_001"
            )
            values = [row.source_system for row in result.select("source_system").collect()]
            assert all(v == "datalake-medallion" for v in values)

    def test_is_deleted_false(self, spark, sample_customers_df):
        """is_deleted must be False for all new records."""
        with patch.dict("sys.modules", {
            "awsglue":               MagicMock(),
            "awsglue.transforms":    MagicMock(),
            "awsglue.utils":         MagicMock(),
            "awsglue.context":       MagicMock(),
            "awsglue.job":           MagicMock(),
            "awsglue.dynamicframe":  MagicMock(),
        }):
            from raw_to_bronze import add_audit_columns

            result = add_audit_columns(
                sample_customers_df, "customers", "dev", "eu-north-1", "jr_001"
            )
            values = [row.is_deleted for row in result.select("is_deleted").collect()]
            assert all(v is False for v in values)

    def test_env_and_region_propagated(self, spark, sample_orders_df):
        """env and region audit columns must match job args."""
        with patch.dict("sys.modules", {
            "awsglue":               MagicMock(),
            "awsglue.transforms":    MagicMock(),
            "awsglue.utils":         MagicMock(),
            "awsglue.context":       MagicMock(),
            "awsglue.job":           MagicMock(),
            "awsglue.dynamicframe":  MagicMock(),
        }):
            from raw_to_bronze import add_audit_columns

            result = add_audit_columns(
                sample_orders_df, "orders", "prelive", "eu-north-1", "jr_002"
            )
            row = result.select("env", "region", "job_run_id").first()
            assert row["env"] == "prelive"
            assert row["region"] == "eu-north-1"
            assert row["job_run_id"] == "jr_002"

    def test_pk_surrogate_not_null(self, spark, sample_customers_df):
        """pk_surrogate must be non-null for every row."""
        with patch.dict("sys.modules", {
            "awsglue":               MagicMock(),
            "awsglue.transforms":    MagicMock(),
            "awsglue.utils":         MagicMock(),
            "awsglue.context":       MagicMock(),
            "awsglue.job":           MagicMock(),
            "awsglue.dynamicframe":  MagicMock(),
        }):
            from raw_to_bronze import add_audit_columns

            result = add_audit_columns(
                sample_customers_df, "customers", "dev", "eu-north-1", "jr_001"
            )
            null_count = result.filter(F.col("pk_surrogate").isNull()).count()
            assert null_count == 0

    def test_record_hash_uniqueness(self, spark, sample_customers_df):
        """record_hash must be unique across distinct rows."""
        with patch.dict("sys.modules", {
            "awsglue":               MagicMock(),
            "awsglue.transforms":    MagicMock(),
            "awsglue.utils":         MagicMock(),
            "awsglue.context":       MagicMock(),
            "awsglue.job":           MagicMock(),
            "awsglue.dynamicframe":  MagicMock(),
        }):
            from raw_to_bronze import add_audit_columns

            result = add_audit_columns(
                sample_customers_df, "customers", "dev", "eu-north-1", "jr_001"
            )
            total = result.count()
            distinct = result.select("record_hash").distinct().count()
            assert total == distinct, "record_hash values are not unique"

    def test_original_columns_preserved(self, spark, sample_customers_df):
        """Original CSV columns must still be present after audit column addition."""
        with patch.dict("sys.modules", {
            "awsglue":               MagicMock(),
            "awsglue.transforms":    MagicMock(),
            "awsglue.utils":         MagicMock(),
            "awsglue.context":       MagicMock(),
            "awsglue.job":           MagicMock(),
            "awsglue.dynamicframe":  MagicMock(),
        }):
            from raw_to_bronze import add_audit_columns

            result = add_audit_columns(
                sample_customers_df, "customers", "dev", "eu-north-1", "jr_001"
            )
            for col in ["customer_id", "name", "email", "country"]:
                assert col in result.columns
