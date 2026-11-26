# IAM Permissions

Three IAM roles are provisioned per environment. Each role follows least-privilege: permissions are scoped to the exact resources and actions each service needs to perform its function.

---

## GlueJobRole-{env}

**Trust principal:** `glue.amazonaws.com`  
**Managed policy attached:** `arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole` (required for Glue to function)  
**Inline policy:** `GlueJobPolicy`

| Action(s) | Resource ARN pattern | Rationale |
|-----------|----------------------|-----------|
| `s3:GetObject` | `{data_lake_bucket_arn}/raw/*` `{data_lake_bucket_arn}/landing/*` | Glue reads source CSV files from the raw landing zone. Write access is intentionally excluded to prevent accidental modification of the source-of-truth layer. |
| `s3:PutObject` `s3:GetObject` `s3:DeleteObject` | `{data_lake_bucket_arn}/bronze/*` `{data_lake_bucket_arn}/gold/*` `{data_lake_bucket_arn}/scripts/*` `{data_lake_bucket_arn}/glue-temp/*` | Glue writes Parquet files to bronze and gold, reads job scripts, and uses the temp prefix for shuffle spill. Delete is required for Glue to overwrite existing files during re-runs. |
| `s3:ListBucket` | `{data_lake_bucket_arn}` | Required for path existence checks and partition discovery within the bucket. |
| `glue:GetDatabase` `glue:CreateDatabase` `glue:UpdateDatabase` `glue:GetTable` `glue:CreateTable` `glue:UpdateTable` `glue:BatchCreatePartition` `glue:GetPartition` `glue:GetPartitions` | `arn:aws:glue:{region}:{account_id}:catalog` `arn:aws:glue:{region}:{account_id}:database/bronze_db_{env}` `arn:aws:glue:{region}:{account_id}:database/gold_db_{env}` `arn:aws:glue:{region}:{account_id}:table/bronze_db_{env}/*` `arn:aws:glue:{region}:{account_id}:table/gold_db_{env}/*` | Glue jobs call `getSink().setCatalogInfo()` to register and update table definitions and partitions in the Data Catalog after each write. Create and Update are needed for idempotent re-runs. |
| `logs:CreateLogGroup` `logs:CreateLogStream` `logs:PutLogEvents` | `arn:aws:logs:{region}:{account_id}:log-group:/aws-glue/*` | Glue writes continuous logs and job diagnostics to CloudWatch under the `/aws-glue/` log group prefix. |

---

## MWAAExecutionRole-{env}

**Trust principals:** `airflow-env.amazonaws.com`, `airflow.amazonaws.com`  
**Inline policy:** `MWAAPolicy`

| Action(s) | Resource ARN pattern | Rationale |
|-----------|----------------------|-----------|
| `glue:StartJobRun` `glue:GetJobRun` `glue:GetJob` `glue:BatchStopJobRun` | `arn:aws:glue:{region}:{account_id}:job/*` | Airflow's `GlueJobOperator` starts Glue jobs, polls their status, and can stop them on timeout. Scoped to all jobs in the account (not specific job names) to allow the same role across environments without updates. |
| `athena:StartQueryExecution` `athena:GetQueryExecution` `athena:GetQueryResults` `athena:StopQueryExecution` | `arn:aws:athena:{region}:{account_id}:workgroup/datalake-{env}` | Airflow's `AthenaOperator` submits CTAS queries and polls for completion. Scoped to the environment-specific workgroup only. |
| `s3:GetObject` `s3:PutObject` `s3:DeleteObject` `s3:ListBucket` | `{mwaa_bucket_arn}` `{mwaa_bucket_arn}/*` | MWAA reads DAG files, plugins, and requirements from its S3 bucket, and writes task logs back to it. |
| `s3:PutObject` | `{data_lake_bucket_arn}/athena-results/*` | Athena writes query result files to this prefix; the MWAA role must be able to write there since the AthenaOperator acts under this role. |
| `logs:CreateLogGroup` `logs:CreateLogStream` `logs:PutLogEvents` `logs:DescribeLogGroups` | `arn:aws:logs:{region}:{account_id}:log-group:airflow-*` | MWAA writes scheduler, worker, webserver, DAG processing, and task logs to CloudWatch log groups named `airflow-{env}-*`. |
| `airflow:PublishMetrics` | `arn:aws:airflow:{region}:{account_id}:environment/datalake-mwaa-{env}` | Required by MWAA to publish environment health metrics to CloudWatch. Without this, the MWAA environment fails to start. |

---

## AthenaQueryRole-{env}

**Trust principal:** `arn:aws:iam::{account_id}:root` (any IAM entity in the account can assume this role)  
**Inline policy:** `AthenaQueryPolicy`

This role is intended for human analysts and BI tools that need to query the gold layer. It is intentionally read-only on data (no S3 write except the results prefix) and restricted to the gold catalog only.

| Action(s) | Resource ARN pattern | Rationale |
|-----------|----------------------|-----------|
| `athena:StartQueryExecution` `athena:GetQueryExecution` `athena:GetQueryResults` `athena:StopQueryExecution` `athena:ListQueryExecutions` `athena:GetWorkGroup` | `arn:aws:athena:{region}:{account_id}:workgroup/datalake-{env}` | Full query lifecycle for ad-hoc analytics. Scoped to the environment-specific workgroup. `ListQueryExecutions` allows users to view their query history. |
| `glue:GetDatabase` `glue:GetTable` `glue:GetTables` `glue:GetPartition` `glue:GetPartitions` | `arn:aws:glue:{region}:{account_id}:catalog` `arn:aws:glue:{region}:{account_id}:database/gold_db_{env}` `arn:aws:glue:{region}:{account_id}:table/gold_db_{env}/*` | Athena calls the Glue Data Catalog to resolve table schemas and partitions before query execution. Scoped to gold only — analysts cannot see bronze or raw catalog entries. |
| `s3:GetObject` | `{data_lake_bucket_arn}/gold/*` `{data_lake_bucket_arn}/athena-results/*` | Athena reads gold Parquet files and analysts can download previous results. Read-only. |
| `s3:ListBucket` | `{data_lake_bucket_arn}` | Required for Athena's S3 path resolution. |
| `s3:PutObject` | `{data_lake_bucket_arn}/athena-results/*` | Athena writes query results on behalf of the query submitter. Scoped to the results prefix only. |
