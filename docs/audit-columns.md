# Audit Columns

Every record written to the bronze layer carries ten audit columns. They are added by `raw_to_bronze.py` and passed through unchanged to the gold layer.

---

## Column Reference

| Column | Type | Source | Description |
|--------|------|--------|-------------|
| `pk_surrogate` | `STRING` | Computed | SHA-256 hash of the table's natural key column(s), concatenated with `\|`. Provides a stable, collision-resistant row identifier independent of storage format. Use for joins across layers and deduplication. |
| `source_system` | `STRING` | Literal | Always `datalake-medallion`. Identifies the ingestion system when data from multiple systems lands in the same catalog. |
| `source_file` | `STRING` | PySpark `input_file_name()` | Full S3 URI of the source CSV file from which this record was read (e.g. `s3://datalake-medallion-dev-eu-north-1/raw/landing/orders/orders_20240115.csv`). Enables tracing a bronze record back to its exact source file. |
| `ingestion_timestamp` | `TIMESTAMP` | PySpark `current_timestamp()` | UTC timestamp at the moment the Glue job wrote this record. Millisecond precision. Use for SLA monitoring and ordering records within the same `ingestion_date`. |
| `ingestion_date` | `DATE` | PySpark `current_date()` | Calendar date of ingestion, used as the Parquet partition key. Keeps related records in the same partition for efficient Athena predicate pushdown. |
| `env` | `STRING` | Job argument `--env` | Environment name (`dev` or `prelive`). Prevents accidental cross-environment queries and simplifies partition-level filtering when environments share the same catalog endpoint. |
| `region` | `STRING` | Job argument `--region` | AWS region of the Glue job execution (e.g. `eu-north-1`). Useful for multi-region audits and cost attribution. |
| `job_run_id` | `STRING` | Glue system arg `JOB_RUN_ID` | Unique identifier of the Glue job run that produced this record (e.g. `jr_abc123def`). Use to replay a specific run, correlate CloudWatch log streams, or identify all records from a failed/successful run. |
| `is_deleted` | `BOOLEAN` | Default `false` | Soft-delete flag. Set to `true` by an upstream deletion propagation process rather than physically removing the row. All gold-layer queries filter `WHERE is_deleted = FALSE`. Bronze retains the full history including deleted records. |
| `record_hash` | `STRING` | Computed | SHA-256 hash of all original (pre-audit) columns, concatenated with `\|`. Use for change-data-capture: compare the current hash against the previous load's hash to detect modified records without comparing every column. |

---

## Rationale

**pk_surrogate vs natural key:** Natural keys can be `NULL`, composite, or change type between schema versions. A SHA-256 hash is always a fixed-length string, regardless of source schema, and allows consistent joins across layers without knowledge of each table's key structure.

**record_hash for CDC:** Storing the hash of all payload columns allows the pipeline to detect changes in a single comparison rather than a column-by-column diff. If `record_hash` matches between two loads, the record is unchanged — no further processing needed.

**ingestion_date as partition key:** Daily or per-load date partitioning is the most common pattern for append-based data lakes. It aligns with the twice-monthly pipeline schedule (1st and 15th) and lets Athena skip entire partitions when analysts filter by load date.

**is_deleted over hard deletes:** Physical deletes from Parquet files require a full partition rewrite. Soft deletes preserve history (required for auditability), allow downstream gold tables to filter consistently, and can be reversed without data loss.

**job_run_id for observability:** Every record carries its producing job run ID. If a job fails midway through a large dataset, you can identify and re-process exactly the partition produced by that run, or exclude incomplete runs from downstream queries.
