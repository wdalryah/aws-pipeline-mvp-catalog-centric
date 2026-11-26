# Architecture

## Overview

`datalake-medallion` implements the [medallion architecture](https://www.databricks.com/glossary/medallion-architecture) on AWS. Data flows through three storage layers — raw, bronze, and gold — each with increasing quality, structure, and business value. All infrastructure is managed with Terraform, all ETL is orchestrated by Amazon MWAA (Airflow), and all deployments are automated via AWS CodePipeline.

The project targets the `eu-north-1` region and supports two environments: `dev` and `prelive`. Every environment is isolated: its own S3 buckets, IAM roles, Glue catalog databases, Athena workgroup, MWAA environment, and pipeline.

---

## Storage Layers

### raw/landing/

**Purpose:** Immutable landing zone for source data as delivered by upstream systems.  
**Format:** CSV (original source format, no transformation).  
**Location:** `s3://datalake-medallion-{env}-eu-north-1/raw/landing/{table}/`  
**Access:** Written by upstream producers; read by Glue raw→bronze jobs.  
**Retention:** Indefinite (source of truth, never overwritten).

### bronze/

**Purpose:** Cleaned, schema-enforced copy of raw data with audit lineage.  
**Format:** Parquet (Snappy compression), partitioned by `ingestion_date`.  
**Location:** `s3://datalake-medallion-{env}-eu-north-1/bronze/{table}/`  
**Access:** Written by Glue PySpark jobs; read by Athena and downstream gold jobs.  
**Retention:** 90 days on STANDARD, then automatically transitions to STANDARD_IA.  
**Registered in:** Glue Data Catalog as `bronze_db_{env}.{table}`.

Audit columns added at this layer:

| Column | Description |
|--------|-------------|
| `pk_surrogate` | SHA-256 of natural key columns |
| `source_system` | Literal `datalake-medallion` |
| `source_file` | S3 path of the source CSV file |
| `ingestion_timestamp` | Timestamp when the record was ingested |
| `ingestion_date` | Date partition key |
| `env` | Environment (dev/prelive) |
| `region` | AWS region |
| `job_run_id` | Glue job run ID for lineage tracing |
| `is_deleted` | Soft delete flag (default `false`) |
| `record_hash` | SHA-256 of all original columns for change detection |

### gold/

**Purpose:** Business-ready, joined, and aggregated semantic tables for analytics consumption.  
**Format:** Parquet (Snappy compression), partitioned by `ingestion_date`.  
**Location:** `s3://datalake-medallion-{env}-eu-north-1/gold/semantic_orders_summary/`  
**Access:** Written by Athena CTAS; read by Athena ad-hoc queries.  
**Retention:** 180 days on STANDARD, then transitions to STANDARD_IA.  
**Registered in:** Glue Data Catalog as `gold_db_{env}.semantic_orders_summary`.

---

## Component Descriptions

### Amazon S3

Two buckets per environment:

- **Data lake bucket** (`datalake-medallion-{env}-{region}`): Hosts all pipeline data (`raw/`, `bronze/`, `gold/`, `scripts/`, `glue-temp/`, `athena-results/`).
- **MWAA bucket** (`datalake-medallion-mwaa-{env}`): Hosts Airflow DAGs and requirements.

Both buckets have versioning enabled, SSE-S3 encryption, and all public access blocked. Lifecycle rules transition bronze after 90 days and gold after 180 days to `STANDARD_IA`.

### AWS Glue

- **Databases:** `bronze_db_{env}` and `gold_db_{env}` in the Glue Data Catalog.
- **Raw→Bronze jobs (3):** One per table (`customers`, `orders`, `products`). Each runs the same `raw_to_bronze.py` PySpark script with table-specific arguments. Glue 4.0, G.1X, 2 workers, 60-minute timeout.
- **Bronze→Gold job (1):** `bronze_to_gold_semantic_orders_{env}` drives an Athena CTAS query via the Athena API. Glue 4.0, G.1X, 2 workers.
- **Crawlers (2):** `bronze_crawler_{env}` runs on the 1st and 15th at 03:00 UTC; `gold_crawler_{env}` at 04:00 UTC. Both update table metadata and partition information in the Data Catalog.

### Amazon Athena

One workgroup `datalake-{env}` per environment. Configuration:

- Results output to `s3://datalake-medallion-{env}-eu-north-1/athena-results/` with SSE-S3 encryption.
- Athena engine version 3 (latest, improved performance and SQL support).
- `enforce_workgroup_configuration = true` prevents clients from overriding result location or encryption.
- CloudWatch metrics publishing enabled for cost and query performance monitoring.

### Amazon MWAA

Environment `datalake-mwaa-{env}` running Airflow 2.8.1.

- **dev:** `mw1.small` (cost-optimised).
- **prelive:** `mw1.medium` (higher scheduler throughput for validation loads).
- DAGs and `requirements.txt` are served from the MWAA S3 bucket.
- All log types (DAG processing, scheduler, task, webserver, worker) write to CloudWatch Logs at INFO level.
- `load_examples = false` to keep the UI uncluttered.

### AWS CodePipeline / CodeBuild

One pipeline per environment: `datalake-pipeline-{env}`.

**Stages:**

1. **Source:** GitHub via CodeStar connection. Triggers on push to `main` (dev) or `prelive` (prelive).
2. **TFPlan:** CodeBuild runs `terraform init`, `validate`, `plan`. Artifact (plan file) passed downstream.
3. **Approval** _(prelive only)_: Manual gate — a reviewer must approve before apply.
4. **TFApply:** CodeBuild runs `terraform apply tfplan`.

CodeBuild uses `aws/codebuild/standard:7.0` and downloads Terraform 1.7.0 at build time.

---

## Data Flow Walkthrough

1. Source files arrive as CSVs in `s3://.../raw/landing/{table}/`.
2. MWAA triggers three Glue jobs in parallel on the 1st and 15th of each month at 02:00 UTC.
3. Each Glue job reads the CSV, adds 10 audit columns, and writes Parquet partitioned by `ingestion_date` to `s3://.../bronze/{table}/`, registering the table in `bronze_db_{env}`.
4. After all three bronze jobs succeed, MWAA triggers an Athena CTAS query that joins `orders ⋈ customers ⋈ products` from the bronze layer, filters soft-deleted rows, and writes the result to `s3://.../gold/semantic_orders_summary/`, registered in `gold_db_{env}`.
5. Analysts query `gold_db_{env}.semantic_orders_summary` via Athena using the `datalake-{env}` workgroup.
6. Glue crawlers run on the 1st and 15th (03:00/04:00 UTC) to keep partition metadata current after each pipeline run.

---

## Full Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        GitHub Repository                            │
│  branch: main (dev) / prelive (prelive)                             │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ push / merge
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     AWS CodePipeline                                │
│                                                                     │
│  [Source: CodeStar/GitHub] → [CodeBuild: TF Plan]                  │
│        → [Manual Approval*] → [CodeBuild: TF Apply]                │
│                              * prelive only                         │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ provisions
              ┌────────────────┼──────────────────────────┐
              ▼                ▼                           ▼
        ┌──────────┐    ┌───────────┐             ┌──────────────┐
        │  S3      │    │  IAM      │             │  Glue        │
        │  buckets │    │  roles    │             │  catalog     │
        │  (2/env) │    │  (3/env)  │             │  (2 DBs/env) │
        └──────────┘    └───────────┘             └──────────────┘
              │                                          │
              │                                          │
              ▼                                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Amazon MWAA (Airflow 2.8.1)                    │
│              DAG: medallion_pipeline (cron: 0 2 1,15 * *)           │
│                                                                     │
│    ┌───────────────┐  ┌──────────────┐  ┌─────────────────┐        │
│    │ GlueJobOp:    │  │ GlueJobOp:   │  │ GlueJobOp:      │        │
│    │ customers     │  │ orders       │  │ products        │        │
│    │ raw→bronze    │  │ raw→bronze   │  │ raw→bronze      │        │
│    └───────┬───────┘  └──────┬───────┘  └────────┬────────┘        │
│            └────────────────┬┘                   │                 │
│                             └───────┬─────────────┘                │
│                                     ▼                              │
│                         ┌───────────────────────┐                  │
│                         │ AthenaOperator:        │                  │
│                         │ gold_semantic_orders   │                  │
│                         │ (CTAS bronze → gold)   │                  │
│                         └───────────────────────┘                  │
└─────────────────────────────────────────────────────────────────────┘
              │
              ▼
S3: datalake-medallion-{env}-eu-north-1/
├── raw/landing/customers/   ← CSV input
├── raw/landing/orders/      ← CSV input
├── raw/landing/products/    ← CSV input
├── bronze/customers/        ← Parquet + audit, partitioned by ingestion_date
├── bronze/orders/           ← Parquet + audit, partitioned by ingestion_date
├── bronze/products/         ← Parquet + audit, partitioned by ingestion_date
├── gold/semantic_orders_summary/   ← Joined gold table (Parquet/Snappy)
├── scripts/glue/jobs/       ← PySpark job scripts
├── glue-temp/               ← Glue shuffle spill
└── athena-results/          ← Athena query output
              │
              ▼
        ┌────────────────────────────────┐
        │  AWS Glue Data Catalog         │
        │  bronze_db_{env}.customers     │
        │  bronze_db_{env}.orders        │
        │  bronze_db_{env}.products      │
        │  gold_db_{env}.semantic_orders │
        └────────────────────────────────┘
              │
              ▼
        ┌──────────────────────┐
        │  Amazon Athena       │
        │  workgroup:          │
        │  datalake-{env}      │
        │  engine version 3    │
        └──────────────────────┘
```

---

## Design Decisions

### Why Parquet + Snappy?

Parquet's columnar layout means Athena reads only the columns required by a query, reducing data scanned and cost. Snappy offers fast compression/decompression with reasonable compression ratios, well-suited to Glue workers where CPU is at a premium. Alternatives like ZSTD offer better compression but add complexity; Gzip is slower to decompress. For this workload, Snappy is the right balance.

### Why partition by `ingestion_date`?

Athena prunes partitions using the `WHERE ingestion_date = ...` predicate, scanning only the data for the requested load window. This is predictable, aligns with the twice-monthly pipeline schedule, and avoids small-file problems that date-based daily partitions can create for infrequent loads.

### Why the medallion pattern?

The three-layer model separates concerns: raw is the immutable record of what arrived; bronze enforces schema and adds traceability; gold delivers business-ready joins without exposing raw complexity to analysts. Each layer is independently reprocessable if upstream logic changes, and the audit columns in bronze make lineage audits straightforward.

### Why MWAA over Step Functions?

MWAA provides a full Airflow UI with task-level logs, retry management, and variable/connection management. The team already uses Airflow idioms. Step Functions would work but would require learning a different orchestration model and loses the Airflow operator ecosystem (native `GlueJobOperator`, `AthenaOperator`).

### Why Athena CTAS for gold instead of a Glue DynamicFrame write?

CTAS executes the join and write in Athena's distributed query engine without spinning up Glue workers, which is cheaper for a join-heavy aggregation over already-columnar Parquet data. The tradeoff is that CTAS cannot overwrite partitions; the pipeline uses INSERT INTO on subsequent runs, so the gold table must be pre-created (by the initial CTAS in `semantic_orders.sql`) before incremental loads begin.
