# Well-Architected Framework Review

This document maps the `datalake-medallion` project to the six pillars of the [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/).

---

## Operational Excellence

> Run and monitor systems to deliver business value and continually improve processes.

| Practice | Implementation |
|----------|---------------|
| **CloudWatch alarms on Glue failures** | Glue jobs emit `glue.ALL.failed` metrics to CloudWatch. Alert on `JobRunFailed > 0` to notify the data-engineering team immediately. Each job has `--enable-metrics` and `--enable-continuous-cloudwatch-log` enabled. |
| **MWAA comprehensive logging** | All five MWAA log types (DAG processing, scheduler, task, webserver, worker) write to CloudWatch at INFO level. Task-level logs link directly from the Airflow UI. |
| **Terraform state versioning** | The S3 state bucket has versioning enabled. Accidental `terraform apply` errors can be rolled back by restoring a previous state version. |
| **Pipeline notifications** | CodePipeline emits execution state events to EventBridge. Wire an EventBridge rule to SNS to notify on pipeline failures or approval requests. |
| **Idempotent jobs** | `raw_to_bronze.py` uses `updateBehavior="UPDATE_IN_DATABASE"` so repeated runs update catalog metadata rather than failing on existing tables. |
| **IaC-only changes** | All infrastructure changes flow through Terraform and CodePipeline. Direct console changes are detected as drift on the next plan. |

---

## Security

> Protect information, systems, and assets while delivering business value through risk assessments and mitigation.

| Practice | Implementation |
|----------|---------------|
| **Least-privilege IAM** | Three scoped roles per environment: `GlueJobRole` (read raw, write bronze/gold), `MWAAExecutionRole` (trigger Glue/Athena, access MWAA bucket), `AthenaQueryRole` (read gold, write results). No wildcard service access. |
| **S3 block public access** | All S3 buckets (data lake, MWAA, artifacts, state) have all four public access block settings enabled. No bucket policy grants public read. |
| **SSE-S3 encryption at rest** | All S3 buckets use AES-256 server-side encryption. Athena results are also encrypted via the workgroup configuration. |
| **No hardcoded credentials** | Glue assumes its IAM role at runtime. MWAA assumes its execution role. GitHub Actions uses OIDC (`role-to-assume`) — no long-lived access keys in secrets. |
| **OIDC for CI/CD** | GitHub Actions authenticates to AWS via OIDC, eliminating the need to rotate static IAM credentials. `permissions.id-token: write` enables the OIDC token request. |
| **Workgroup-enforced results** | `enforce_workgroup_configuration = true` on the Athena workgroup prevents any query client from redirecting results to an unencrypted or public bucket. |
| **DynamoDB state lock** | Concurrent `terraform apply` runs are prevented by a DynamoDB lock, eliminating state corruption that could lead to unintended resource creation or deletion. |

---

## Reliability

> Ensure a workload performs its intended function correctly and consistently when expected.

| Practice | Implementation |
|----------|---------------|
| **S3 versioning** | The data lake and MWAA S3 buckets have versioning enabled. Accidental overwrites or deletions are recoverable. |
| **Glue job retries** | The Airflow `GlueJobOperator` is configured with `retries=2` and `retry_delay=5m`. Transient Glue API failures or capacity constraints are automatically retried before alerting. |
| **MWAA task retries** | DAG `default_args` sets `retries=2` and `execution_timeout=2h`, ensuring tasks retry on transient failures and do not hang indefinitely. |
| **DynamoDB state lock** | Prevents split-brain Terraform state, which could cause duplicate or conflicting resource creation. |
| **Idempotent pipeline** | Re-running the full pipeline for the same `ingestion_date` overwrites existing bronze partitions cleanly. The soft-delete `is_deleted` flag preserves history. |
| **max_active_runs=1** | The DAG limits itself to one active run, preventing concurrent executions from writing conflicting partitions. |

---

## Performance Efficiency

> Use computing resources efficiently to meet requirements and maintain efficiency as demand changes.

| Practice | Implementation |
|----------|---------------|
| **Parquet + Snappy** | Columnar Parquet format lets Athena skip non-queried columns. Snappy compression reduces data scanned. Query costs and latency are proportional to columns and rows read. |
| **ingestion_date partitioning** | Bronze and gold tables are partitioned by `ingestion_date`. Athena pushes partition predicates to S3 key prefixes, skipping irrelevant load windows entirely. |
| **Athena engine version 3** | The latest Athena engine improves CTAS performance, `UNNEST`, window functions, and join strategies over engine v2. |
| **G.1X Glue workers** | The smallest Glue worker type (4 vCPU, 16 GiB) is sufficient for the CSV→Parquet conversion workload. Upgrading to G.2X is straightforward in `job_config.json` if data volumes grow. |
| **Parallel bronze ingestion** | All three raw→bronze Glue jobs run in parallel (not sequentially), reducing total wall-clock time for the pipeline. |
| **Crawlers on 1st/15th** | Crawlers run after the pipeline, not continuously, keeping catalog metadata fresh without incurring unnecessary crawler costs. |

---

## Cost Optimization

> Avoid unnecessary costs and understand spending over time.

| Practice | Implementation |
|----------|---------------|
| **Smallest viable Glue workers** | `G.1X` with 2 workers per job. Each job runs for ≤ 60 minutes. Total monthly DPU cost is minimal for the twice-monthly schedule. |
| **mw1.small for dev** | Dev uses the smallest MWAA size. Prelive uses `mw1.medium` only because it handles more validation load. Neither environment uses `mw1.large` unless required. |
| **S3 lifecycle to STANDARD_IA** | Bronze transitions to STANDARD_IA after 90 days; gold after 180 days. Access patterns after those windows are infrequent reads for historical analysis, which STANDARD_IA is priced for. |
| **Pay-per-query Athena** | Athena charges per TB scanned. Parquet + Snappy + partition pruning minimises the data scanned per query. No reserved capacity is required at this workload size. |
| **PAY_PER_REQUEST DynamoDB** | The state lock table uses on-demand capacity. Lock operations are infrequent (one per deploy), so provisioned capacity would be wasteful. |
| **Artifact bucket for CodeBuild** | Build artifacts are stored in a versioned bucket; older versions can be expired with a lifecycle rule (not currently configured — add one if artifact retention accumulates significant storage). |

---

## Sustainability

> Minimise the environmental impact of running cloud workloads.

| Practice | Implementation |
|----------|---------------|
| **Minimal worker counts** | 2 workers per Glue job and `mw1.small` for dev keep compute to what is actually required. Right-sizing avoids idle capacity. |
| **Schedule-based processing** | The pipeline runs twice a month, not continuously. Compute resources are allocated only when needed. |
| **Lifecycle policies reduce storage footprint** | Bronze and gold data transitions to STANDARD_IA, which uses less redundant storage infrastructure than STANDARD. |
| **Columnar Parquet reduces I/O** | Less data read from S3 per query means less compute in Athena and lower energy consumption per query. |
| **eu-north-1 (Stockholm)** | AWS Stockholm runs on 100% renewable energy (AWS Sustainability Report). Placing workloads there reduces carbon footprint compared to regions with higher carbon intensity. |
