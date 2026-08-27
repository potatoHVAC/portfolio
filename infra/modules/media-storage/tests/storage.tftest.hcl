variables {
  account_id = "123456789012"
  region     = "us-west-2"
}

mock_provider "aws" {
  alias = "mock"
}

run "private_media_storage" {
  command = plan

  providers = {
    aws = aws.mock
  }

  assert {
    condition = aws_s3_bucket.media["originals"].bucket == "speerd-portfolio-originals-123456789012-us-west-2" && (
      aws_s3_bucket.media["delivery"].bucket == "speerd-portfolio-media-123456789012-us-west-2"
    )
    error_message = "Media bucket names must be deterministic and account/region scoped."
  }

  assert {
    condition = alltrue([
      for bucket in aws_s3_bucket.media : bucket.force_destroy == false
    ])
    error_message = "Media buckets must never allow force_destroy."
  }

  assert {
    condition = alltrue([
      for controls in aws_s3_bucket_ownership_controls.media :
      one(controls.rule).object_ownership == "BucketOwnerEnforced"
    ])
    error_message = "Media buckets must reject ACL ownership."
  }

  assert {
    condition = alltrue([
      for access in aws_s3_bucket_public_access_block.media :
      access.block_public_acls && access.block_public_policy &&
      access.ignore_public_acls && access.restrict_public_buckets
    ])
    error_message = "Every S3 public-access block must be enabled for both media buckets."
  }

  assert {
    condition = alltrue([
      for encryption in aws_s3_bucket_server_side_encryption_configuration.media :
      one(one(encryption.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    ])
    error_message = "Media buckets must use SSE-S3 encryption."
  }

  assert {
    condition     = one(aws_s3_bucket_versioning.originals.versioning_configuration).status == "Enabled"
    error_message = "The originals archive must have versioning enabled."
  }

  assert {
    condition = alltrue([
      for lifecycle in aws_s3_bucket_lifecycle_configuration.media :
      one(lifecycle.rule[*].status) == "Enabled" &&
      one(flatten(lifecycle.rule[*].abort_incomplete_multipart_upload)[*].days_after_initiation) == 7
    ])
    error_message = "Both buckets must abort incomplete multipart uploads after seven days."
  }

  assert {
    condition = alltrue([
      for statement in jsondecode(aws_s3_bucket_policy.originals.policy).Statement :
      statement.Effect == "Deny" && statement.Action == "s3:*"
    ])
    error_message = "The originals policy may contain only the TLS-deny statement, never a read grant."
  }

  assert {
    condition = (
      jsondecode(aws_s3_bucket_policy.originals.policy).Statement[0].Condition.Bool["aws:SecureTransport"] == "false"
    )
    error_message = "The originals policy must deny non-TLS transport."
  }
}
