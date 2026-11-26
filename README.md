# datalake-medallion

Production-grade AWS Data Lakehouse using the medallion architecture (raw → bronze → gold). Terraform manages all infrastructure across two environments (dev, prelive) in `eu-north-1`. Amazon MWAA orchestrates the ETL pipeline; AWS Glue handles raw→bronze transformation via PySpark; Athena executes CTAS queries for the gold layer. GitHub Actions validates on every pull request; CodePipeline deploys on merge.

---

## Architecture

### CI/CD Flow

```
GitHub PR ──► GitHub Actions (terraform fmt/validate/plan)
                     │
                     ▼ merge to main/prelive
             AWS CodePipeline
                     │
          ┌──────────┴──────────┐
          ▼                     ▼
   CodeBuild: TF Plan    [Manual Approval]  ← prelive only
          │                     │
          └──────────┬──────────┘
                     ▼
           CodeBuild: TF Apply
                     │
                     ▼
           AWS Resources (S3, Glue, Athena, MWAA)
```

### Data Pipeline Flow

```
                     MWAA (Airflow 2.8.1)
                     Schedules: 1st & 15th at 02:00 UTC
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
  Glue: customers   Glue: orders    Glue: products
  raw→bronze        raw→bronze      raw→bronze
  (PySpark)         (PySpark)       (PySpark)
          │                │                │
          └────────────────┼────────────────┘
                           ▼
                S3: s3://datalake-medallion-{env}-eu-north-1/
                  ├── raw/landing/{table}/     ← CSV source files
                  ├── bronze/{table}/          ← Parquet + audit cols
                  ├── gold/semantic_orders/    ← Joined gold table
                  └── athena-results/          ← Query output

                           │ (after all bronze complete)
                           ▼
                  Athena CTAS (engine v3)
                  bronze orders ⋈ customers ⋈ products
                           │
                           ▼
                  S3 gold/semantic_orders_summary/
                  (Parquet/Snappy, partitioned by ingestion_date)
                           │
                           ▼
                  Athena ad-hoc queries via gold_db_{env}
```

---

## Prerequisites

| Tool | Minimum version |
|------|----------------|
| Terraform | >= 1.6 |
| Python | 3.11+ |
| AWS CLI | v2.42+ |
| uv | latest |

You also need:
- An AWS account with sufficient permissions to create S3, Glue, IAM, Athena, MWAA, CodePipeline, and CodeBuild resources.
- A GitHub repository and a GitHub organization for the CodeStar connection.
- Two private subnets and one security group in `eu-north-1` for MWAA.

---

## Quick Start

### 1. Bootstrap the Terraform backend (run once)

```bash
make bootstrap
```

This creates the shared S3 state bucket and DynamoDB lock table. After it completes, replace `ACCOUNT_ID_PLACEHOLDER` in both `infra/terraform/environments/dev/main.tf` and `infra/terraform/environments/prelive/main.tf` with your actual AWS account ID.

### 2. Fill in tfvars

Edit `infra/terraform/environments/dev/terraform.tfvars`:

```hcl
github_owner       = "your-github-org"
subnet_ids         = ["subnet-xxxxxxxx", "subnet-yyyyyyyy"]
security_group_ids = ["sg-zzzzzzzz"]
```

### 3. Deploy dev

```bash
make plan-dev
make apply-dev
```

### 4. Upload Glue scripts and Airflow DAGs

```bash
make upload-scripts-dev
make upload-dags-dev
```

### 5. Activate the CodeStar connection

After `apply-dev`, the CodeStar GitHub connection is in `PENDING` state. Go to **AWS Console → Developer Tools → Connections** and click **Update pending connection** to authorize it.

### 6. Deploy prelive

```bash
make plan-prelive
make apply-prelive CONFIRM=yes
```

---

## Environment Variables Reference

| Variable | Used in | Description |
|----------|---------|-------------|
| `env` | Airflow Variable | Environment name (`dev` or `prelive`) |
| `aws_region` | Airflow Variable | AWS region (default: `eu-north-1`) |
| `data_lake_bucket` | Airflow Variable | Data lake S3 bucket name |
| `athena_workgroup` | Airflow Variable | Athena workgroup name |
| `TF_VAR_github_owner` | GitHub Actions | GitHub org/user for CodeStar connection |
| `TF_VAR_github_repo` | GitHub Actions | Repository name |
| `AWS_OIDC_ROLE_ARN_DEV` | GitHub Actions Secret | IAM role for OIDC auth in dev |
| `AWS_OIDC_ROLE_ARN_PRELIVE` | GitHub Actions Secret | IAM role for OIDC auth in prelive |
| `GITHUB_ORG` | GitHub Actions Secret | GitHub organization name |

---

## Makefile Targets

| Target | Description |
|--------|-------------|
| `help` | Show all available targets |
| `bootstrap` | Create Terraform state backend (run once) |
| `fmt` | Format all Terraform files recursively |
| `validate` | Validate both environments without backend |
| `plan-dev` | Terraform plan for dev |
| `apply-dev` | Terraform apply for dev |
| `destroy-dev` | Destroy dev (requires `CONFIRM=yes`) |
| `plan-prelive` | Terraform plan for prelive |
| `apply-prelive` | Terraform apply for prelive (requires `CONFIRM=yes`) |
| `destroy-prelive` | Destroy prelive (requires `CONFIRM=yes`) |
| `upload-scripts` | Sync Glue scripts to dev bucket |
| `upload-scripts-dev` | Sync Glue scripts to dev bucket |
| `upload-scripts-prelive` | Sync Glue scripts to prelive bucket |
| `upload-dags` | Sync DAGs + requirements to dev MWAA bucket |
| `upload-dags-dev` | Sync DAGs + requirements to dev MWAA bucket |
| `upload-dags-prelive` | Sync DAGs + requirements to prelive MWAA bucket |

---

## Project Structure

```
datalake-medallion/
├── .kiro/specs/datalake.md              # Kiro project spec
├── .github/workflows/terraform-ci.yml  # GitHub Actions CI
├── infra/terraform/
│   ├── backend/bootstrap.tf             # State backend (apply once)
│   ├── modules/
│   │   ├── s3/                          # Data lake + MWAA S3 buckets
│   │   ├── iam/                         # Glue, MWAA, Athena roles
│   │   ├── glue/                        # Databases, jobs, crawlers
│   │   ├── athena/                      # Athena workgroup
│   │   ├── mwaa/                        # MWAA environment
│   │   └── cicd/                        # CodePipeline + CodeBuild
│   └── environments/
│       ├── dev/                         # Dev environment root module
│       └── prelive/                     # Prelive environment root module
├── glue/
│   ├── jobs/raw_to_bronze/              # PySpark job + config
│   ├── jobs/bronze_to_gold/             # Athena CTAS SQL
│   └── tests/                           # pytest unit tests
├── airflow/
│   ├── dags/medallion_pipeline.py       # Main orchestration DAG
│   └── requirements.txt
├── data/dummy/                          # Sample CSV data
├── docs/
│   ├── architecture.md
│   ├── iam-permissions.md
│   ├── audit-columns.md
│   └── well-architected.md
├── Makefile
└── README.md
```
