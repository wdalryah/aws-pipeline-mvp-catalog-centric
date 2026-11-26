data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# CodePipeline IAM Role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "codepipeline_role" {
  name = "CodePipelineRole-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "CodePipelinePolicy-${var.env}"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["codebuild:BatchGetBuilds", "codebuild:StartBuild", "codebuild:StopBuild"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["codestar-connections:UseConnection"]
        Resource = aws_codestarconnections_connection.github.arn
      },
      {
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# CodeBuild IAM Role
# ---------------------------------------------------------------------------
resource "aws_iam_role" "codebuild_role" {
  name = "CodeBuildRole-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "codebuild_policy" {
  name = "CodeBuildPolicy-${var.env}"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ArtifactsAccess"
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*",
        ]
      },
      {
        Sid      = "CloudWatchLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/codebuild/*"]
      },
      {
        Sid    = "TerraformStateAccess"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::datalake-medallion-tfstate-${var.account_id}",
          "arn:aws:s3:::datalake-medallion-tfstate-${var.account_id}/*",
        ]
      },
      {
        Sid    = "TerraformStateLock"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable",
        ]
        Resource = "arn:aws:dynamodb:${var.region}:${var.account_id}:table/datalake-medallion-tflock"
      },
      {
        # NOTE: Broad permissions are required for Terraform to provision all
        # project resources. Scope this down per the principle of least privilege
        # once the full resource set is known and stable.
        Sid      = "TerraformProvisionAccess"
        Effect   = "Allow"
        Action   = ["*"]
        Resource = "*"
      },
      {
        Sid      = "PassRole"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# CodeStar Connection (GitHub)
# ---------------------------------------------------------------------------
resource "aws_codestarconnections_connection" "github" {
  name          = "github-${var.env}"
  provider_type = "GitHub"

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Artifacts S3 bucket
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "artifacts" {
  bucket = "datalake-medallion-artifacts-${var.env}-${var.region}"

  tags = merge(var.tags, {
    Name = "datalake-medallion-artifacts-${var.env}-${var.region}"
  })
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# CodeBuild Project: Terraform Plan
# ---------------------------------------------------------------------------
resource "aws_codebuild_project" "tf_plan" {
  name         = "datalake-tf-plan-${var.env}"
  description  = "Runs terraform init and plan for the ${var.env} environment."
  service_role = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type         = "LINUX_CONTAINER"
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:7.0"

    environment_variable {
      name  = "ENV"
      value = var.env
    }

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.region
    }

    environment_variable {
      name  = "TF_WORKING_DIR"
      value = "infra/terraform/environments/${var.env}"
    }
  }

  source {
    type = "CODEPIPELINE"
    buildspec = yamlencode({
      version = "0.2"
      phases = {
        install = {
          commands = [
            "wget -q https://releases.hashicorp.com/terraform/1.7.0/terraform_1.7.0_linux_amd64.zip",
            "unzip -q terraform_1.7.0_linux_amd64.zip -d /usr/local/bin/",
            "terraform version",
          ]
        }
        build = {
          commands = [
            "cd $TF_WORKING_DIR",
            "terraform init -input=false",
            "terraform validate",
            "terraform plan -no-color -out=tfplan",
          ]
        }
        post_build = {
          commands = ["echo 'terraform plan complete'"]
        }
      }
      artifacts = {
        files          = ["$TF_WORKING_DIR/tfplan", "$TF_WORKING_DIR/.terraform.lock.hcl"]
        discard-paths  = "no"
        base-directory = "."
      }
    })
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# CodeBuild Project: Terraform Apply
# ---------------------------------------------------------------------------
resource "aws_codebuild_project" "tf_apply" {
  name         = "datalake-tf-apply-${var.env}"
  description  = "Runs terraform apply for the ${var.env} environment."
  service_role = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type         = "LINUX_CONTAINER"
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:7.0"

    environment_variable {
      name  = "ENV"
      value = var.env
    }

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.region
    }

    environment_variable {
      name  = "TF_WORKING_DIR"
      value = "infra/terraform/environments/${var.env}"
    }
  }

  source {
    type = "CODEPIPELINE"
    buildspec = yamlencode({
      version = "0.2"
      phases = {
        install = {
          commands = [
            "wget -q https://releases.hashicorp.com/terraform/1.7.0/terraform_1.7.0_linux_amd64.zip",
            "unzip -q terraform_1.7.0_linux_amd64.zip -d /usr/local/bin/",
            "terraform version",
          ]
        }
        build = {
          commands = [
            "cd $TF_WORKING_DIR",
            "terraform init -input=false",
            "terraform apply -auto-approve -input=false tfplan",
          ]
        }
        post_build = {
          commands = ["echo 'terraform apply complete'"]
        }
      }
    })
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# CodePipeline
# ---------------------------------------------------------------------------
resource "aws_codepipeline" "datalake" {
  name     = "datalake-pipeline-${var.env}"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.artifacts.bucket
  }

  stage {
    name = "Source"

    action {
      name             = "GitHubSource"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceArtifact"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = "${var.github_owner}/${var.github_repo}"
        BranchName       = var.github_branch
        DetectChanges    = "true"
      }
    }
  }

  stage {
    name = "TFPlan"

    action {
      name             = "TerraformPlan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceArtifact"]
      output_artifacts = ["PlanArtifact"]

      configuration = {
        ProjectName = aws_codebuild_project.tf_plan.name
      }
    }
  }

  dynamic "stage" {
    for_each = var.require_approval ? [1] : []

    content {
      name = "Approval"

      action {
        name     = "ManualApproval"
        category = "Approval"
        owner    = "AWS"
        provider = "Manual"
        version  = "1"

        configuration = {
          CustomData = "Review the Terraform plan for ${var.env} before applying."
        }
      }
    }
  }

  stage {
    name = "TFApply"

    action {
      name            = "TerraformApply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact", "PlanArtifact"]

      configuration = {
        ProjectName   = aws_codebuild_project.tf_apply.name
        PrimarySource = "SourceArtifact"
      }
    }
  }

  tags = var.tags
}
