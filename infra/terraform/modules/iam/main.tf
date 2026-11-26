# ---------------------------------------------------------------------------
# IAM Role 1: GlueJobRole
# ---------------------------------------------------------------------------
resource "aws_iam_role" "glue_job_role" {
  name = "GlueJobRole-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "glue.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_job_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_job_policy" {
  name = "GlueJobPolicy"
  role = aws_iam_role.glue_job_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadRawLanding"
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = [
          "${var.data_lake_bucket_arn}/raw/*",
          "${var.data_lake_bucket_arn}/landing/*",
        ]
      },
      {
        Sid    = "ReadWriteBronzeGoldScripts"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = [
          "${var.data_lake_bucket_arn}/bronze/*",
          "${var.data_lake_bucket_arn}/gold/*",
          "${var.data_lake_bucket_arn}/scripts/*",
          "${var.data_lake_bucket_arn}/glue-temp/*",
        ]
      },
      {
        Sid      = "ListDataLakeBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [var.data_lake_bucket_arn]
      },
      {
        Sid    = "GlueCatalogAccess"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:CreateDatabase",
          "glue:UpdateDatabase",
          "glue:GetTable",
          "glue:CreateTable",
          "glue:UpdateTable",
          "glue:BatchCreatePartition",
          "glue:GetPartition",
          "glue:GetPartitions",
        ]
        Resource = [
          "arn:aws:glue:${var.region}:${var.account_id}:catalog",
          "arn:aws:glue:${var.region}:${var.account_id}:database/bronze_db_${var.env}",
          "arn:aws:glue:${var.region}:${var.account_id}:database/gold_db_${var.env}",
          "arn:aws:glue:${var.region}:${var.account_id}:table/bronze_db_${var.env}/*",
          "arn:aws:glue:${var.region}:${var.account_id}:table/gold_db_${var.env}/*",
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = ["arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws-glue/*"]
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# IAM Role 2: MWAAExecutionRole
# ---------------------------------------------------------------------------
resource "aws_iam_role" "mwaa_execution_role" {
  name = "MWAAExecutionRole-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "airflow-env.amazonaws.com" }
        Action    = "sts:AssumeRole"
      },
      {
        Effect    = "Allow"
        Principal = { Service = "airflow.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "mwaa_policy" {
  name = "MWAAPolicy"
  role = aws_iam_role.mwaa_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GlueJobControl"
        Effect = "Allow"
        Action = [
          "glue:StartJobRun",
          "glue:GetJobRun",
          "glue:GetJob",
          "glue:BatchStopJobRun",
        ]
        Resource = ["arn:aws:glue:${var.region}:${var.account_id}:job/*"]
      },
      {
        Sid    = "AthenaQueryAccess"
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:StopQueryExecution",
        ]
        Resource = ["arn:aws:athena:${var.region}:${var.account_id}:workgroup/datalake-${var.env}"]
      },
      {
        Sid    = "MWAABucketAccess"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          var.mwaa_bucket_arn,
          "${var.mwaa_bucket_arn}/*",
        ]
      },
      {
        Sid      = "AthenaResultsWrite"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${var.data_lake_bucket_arn}/athena-results/*"]
      },
      {
        Sid    = "MWAACloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
        ]
        Resource = ["arn:aws:logs:${var.region}:${var.account_id}:log-group:airflow-*"]
      },
      {
        Sid      = "MWAAMetrics"
        Effect   = "Allow"
        Action   = ["airflow:PublishMetrics"]
        Resource = ["arn:aws:airflow:${var.region}:${var.account_id}:environment/datalake-mwaa-${var.env}"]
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# IAM Role 3: AthenaQueryRole
# ---------------------------------------------------------------------------
resource "aws_iam_role" "athena_query_role" {
  name = "AthenaQueryRole-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.account_id}:root" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "athena_query_policy" {
  name = "AthenaQueryPolicy"
  role = aws_iam_role.athena_query_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AthenaWorkgroupAccess"
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:StopQueryExecution",
          "athena:ListQueryExecutions",
          "athena:GetWorkGroup",
        ]
        Resource = ["arn:aws:athena:${var.region}:${var.account_id}:workgroup/datalake-${var.env}"]
      },
      {
        Sid    = "GlueCatalogRead"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions",
        ]
        Resource = [
          "arn:aws:glue:${var.region}:${var.account_id}:catalog",
          "arn:aws:glue:${var.region}:${var.account_id}:database/gold_db_${var.env}",
          "arn:aws:glue:${var.region}:${var.account_id}:table/gold_db_${var.env}/*",
        ]
      },
      {
        Sid    = "S3GoldRead"
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = [
          "${var.data_lake_bucket_arn}/gold/*",
          "${var.data_lake_bucket_arn}/athena-results/*",
        ]
      },
      {
        Sid      = "S3ListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [var.data_lake_bucket_arn]
      },
      {
        Sid      = "S3AthenaResultsWrite"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${var.data_lake_bucket_arn}/athena-results/*"]
      }
    ]
  })
}
