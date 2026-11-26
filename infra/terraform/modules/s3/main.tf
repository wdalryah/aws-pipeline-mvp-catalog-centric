data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Main data lake bucket
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "data_lake" {
  bucket = "${var.project}-${var.env}-${var.region}"

  tags = merge(var.tags, {
    Name = "${var.project}-${var.env}-${var.region}"
  })
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    id     = "bronze-to-ia"
    status = "Enabled"

    filter {
      prefix = "bronze/"
    }

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
  }

  rule {
    id     = "gold-to-ia"
    status = "Enabled"

    filter {
      prefix = "gold/"
    }

    transition {
      days          = 180
      storage_class = "STANDARD_IA"
    }
  }
}

# ---------------------------------------------------------------------------
# MWAA bucket
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "mwaa" {
  bucket = "${var.project}-mwaa-${var.env}"

  tags = merge(var.tags, {
    Name = "${var.project}-mwaa-${var.env}"
  })
}

resource "aws_s3_bucket_versioning" "mwaa" {
  bucket = aws_s3_bucket.mwaa.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mwaa" {
  bucket = aws_s3_bucket.mwaa.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "mwaa" {
  bucket = aws_s3_bucket.mwaa.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
