# Kiro Spec: datalake-medallion

## Project Summary

`datalake-medallion` is a production-grade AWS Data Lakehouse built on the medallion architecture pattern (raw → bronze → gold). It is designed for two environments (`dev` and `prelive`) in `eu-north-1`, fully managed by Terraform and deployed via GitHub Actions + AWS CodePipeline.

---

## Components

### Infrastructure (Terraform)

| Component | Resource | Per-env |
|-----------|----------|---------|
| S3 data lake bucket | `datalake-medallion-{env}-eu-north-1` | ✓ |
| S3 MWAA bucket | `datalake-medallion-mwaa-{env}` | ✓ |
| IAM GlueJobRole | `GlueJobRole-{env}` | ✓ |
| IAM MWAAExecutionRole | `MWAAExecutionRole-{env}` | ✓ |
| IAM AthenaQueryRole | `AthenaQueryRole-{env}` | ✓ |
| Glue DB (bronze) | `bronze_db_{env}` | ✓ |
| Glue DB (gold) | `gold_db_{env}` | ✓ |
| Glue jobs | `raw_to_bronze_{customers,orders,products}_{env}` | ✓ |
| Glue job | `bronze_to_gold_semantic_orders_{env}` | ✓ |
| Glue crawlers | `bronze_crawler_{env}`, `gold_crawler_{env}` | ✓ |
| Athena workgroup | `datalake-{env}` | ✓ |
| MWAA environment | `datalake-mwaa-{env}` | ✓ |
| CodePipeline | `datalake-pipeline-{env}` | ✓ |
| CodeBuild (plan) | `datalake-tf-plan-{env}` | ✓ |
| CodeBuild (apply) | `datalake-tf-apply-{env}` | ✓ |
| CodeStar connection | `github-{env}` | ✓ |

### Terraform Backend (shared, applied once)

| Resource | Name |
|----------|------|
| S3 state bucket | `datalake-medallion-tfstate-{account_id}` |
| DynamoDB lock table | `datalake-medallion-tflock` |

---

## Environments

### dev

- Region: `eu-north-1`
- MWAA class: `mw1.small`
- Pipeline: no manual approval gate
- GitHub branch: `main`

### prelive

- Region: `eu-north-1`
- MWAA class: `mw1.medium`
- Pipeline: manual approval required between TF Plan and TF Apply
- GitHub branch: `prelive`

---

## Data Flow

```
S3 raw/landing/{table}/ (CSV)
  │
  ├─ Glue: raw_to_bronze_customers_{env}  ─┐
  ├─ Glue: raw_to_bronze_orders_{env}     ─┤ parallel
  └─ Glue: raw_to_bronze_products_{env}  ─┘
                │
                ▼ (all three complete)
  S3 bronze/{table}/ (Parquet, partitioned by ingestion_date)
  Glue Catalog: bronze_db_{env}.{table}
                │
                ▼
  Athena CTAS: orders ⋈ customers ⋈ products
                │
                ▼
  S3 gold/semantic_orders_summary/ (Parquet/Snappy)
  Glue Catalog: gold_db_{env}.semantic_orders_summary
```

---

## Audit Columns (bronze layer)

All 10 audit columns are added to every bronze table by `raw_to_bronze.py`:

- `pk_surrogate` — SHA-256 of natural keys
- `source_system` — literal `datalake-medallion`
- `source_file` — S3 URI of the source CSV
- `ingestion_timestamp` — UTC timestamp of write
- `ingestion_date` — partition key (DATE)
- `env` — environment name
- `region` — AWS region
- `job_run_id` — Glue job run ID
- `is_deleted` — soft delete flag (default `false`)
- `record_hash` — SHA-256 of all original columns

---

## Key Files

| File | Purpose |
|------|---------|
| `infra/terraform/backend/bootstrap.tf` | Creates state bucket and DynamoDB lock (apply once) |
| `infra/terraform/environments/dev/main.tf` | Dev root module — calls all 6 child modules |
| `infra/terraform/environments/prelive/main.tf` | Prelive root module |
| `infra/terraform/modules/s3/main.tf` | S3 bucket definitions with lifecycle and encryption |
| `infra/terraform/modules/iam/main.tf` | All 3 IAM roles and their inline policies |
| `infra/terraform/modules/glue/main.tf` | Glue databases, jobs (for_each), and crawlers |
| `infra/terraform/modules/athena/main.tf` | Athena workgroup with engine v3 |
| `infra/terraform/modules/mwaa/main.tf` | MWAA environment with full logging config |
| `infra/terraform/modules/cicd/main.tf` | CodePipeline with dynamic approval stage |
| `glue/jobs/raw_to_bronze/raw_to_bronze.py` | PySpark script: CSV → Parquet + 10 audit columns |
| `glue/jobs/bronze_to_gold/semantic_orders.sql` | Athena CTAS: bronze orders ⋈ customers ⋈ products |
| `glue/tests/test_raw_to_bronze.py` | pytest unit tests (local PySpark, no Glue required) |
| `airflow/dags/medallion_pipeline.py` | Airflow DAG: parallel bronze → gold |

---

## How to Work With This Project

### First-time setup

1. Apply the backend: `make bootstrap`
2. Replace `ACCOUNT_ID_PLACEHOLDER` in both `environments/*/main.tf` with your AWS account ID.
3. Fill in `terraform.tfvars` with real `github_owner`, `subnet_ids`, and `security_group_ids`.
4. Run `make plan-dev` then `make apply-dev`.
5. After apply, activate the CodeStar connection in the AWS Console (Developer Tools → Connections).
6. Run `make upload-scripts-dev && make upload-dags-dev`.

### Adding a new table

1. Add the table name to `local.raw_to_bronze_tables` in `modules/glue/main.tf`.
2. Add the natural key to `NATURAL_KEYS` in `raw_to_bronze.py`.
3. Add the natural key to `job_config.json`.
4. Add the table to the Airflow DAG as a new `GlueJobOperator`.
5. Add the new fixture and test cases in `test_raw_to_bronze.py`.
6. Run `terraform plan` to review the new Glue job resource before applying.

### Running tests

```bash
# Install test dependencies (uv recommended)
uv pip install pyspark pytest

# Run unit tests
pytest glue/tests/ -v
```

### Deploying to prelive

```bash
make plan-prelive
# Review the plan output carefully
make apply-prelive CONFIRM=yes
make upload-scripts-prelive
make upload-dags-prelive
```

---

## Security Notes

- Never commit real values to `terraform.tfvars` for `subnet_ids`, `security_group_ids`, or `github_owner` to a public repository.
- The `ACCOUNT_ID_PLACEHOLDER` in `main.tf` backend blocks must be replaced before `terraform init` will succeed.
- The CodeStar connection is created in `PENDING` state and **must be manually activated** in the AWS Console before the pipeline can pull source code.
- GitHub Actions uses OIDC (`AWS_OIDC_ROLE_ARN_DEV` / `AWS_OIDC_ROLE_ARN_PRELIVE` secrets) — no static IAM keys are used.
