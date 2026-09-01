locals {
  buckets = {
    originals = "speerd-portfolio-originals-${var.account_id}-${var.region}"
    delivery  = "speerd-portfolio-media-${var.account_id}-${var.region}"
  }
}

resource "aws_s3_bucket" "media" {
  for_each = local.buckets

  bucket        = each.value
  force_destroy = false
}

resource "aws_s3_bucket_ownership_controls" "media" {
  for_each = local.buckets

  bucket = aws_s3_bucket.media[each.key].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  for_each = local.buckets

  bucket = aws_s3_bucket.media[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "media" {
  for_each = local.buckets

  bucket = aws_s3_bucket.media[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "originals" {
  bucket = aws_s3_bucket.media["originals"].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "media" {
  for_each = local.buckets

  bucket = aws_s3_bucket.media[each.key].id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

locals {
  originals_tls_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.media["originals"].arn,
          "${aws_s3_bucket.media["originals"].arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  }
}

# Only the originals policy belongs to this state. The media-access state owns
# the delivery bucket's complete policy.
resource "aws_s3_bucket_policy" "originals" {
  bucket = aws_s3_bucket.media["originals"].id
  policy = jsonencode(local.originals_tls_policy)

  depends_on = [aws_s3_bucket_public_access_block.media]
}
