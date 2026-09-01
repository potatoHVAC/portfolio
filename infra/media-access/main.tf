data "terraform_remote_state" "global" {
  backend = "s3"

  config = {
    bucket = "speerd-portfolio-tfstate"
    key    = "global/terraform.tfstate"
    region = "us-west-2"
  }
}

data "terraform_remote_state" "dev" {
  backend = "s3"

  config = {
    bucket = "speerd-portfolio-tfstate"
    key    = "dev/terraform.tfstate"
    region = "us-west-2"
  }
}

data "terraform_remote_state" "prod" {
  backend = "s3"

  config = {
    bucket = "speerd-portfolio-tfstate"
    key    = "prod/terraform.tfstate"
    region = "us-west-2"
  }
}

locals {
  delivery_bucket_name = data.terraform_remote_state.global.outputs.media_delivery_bucket_name
  delivery_bucket_arn  = data.terraform_remote_state.global.outputs.media_delivery_bucket_arn
  distribution_arns = [
    data.terraform_remote_state.dev.outputs.distribution_arn,
    data.terraform_remote_state.prod.outputs.distribution_arn,
  ]

  delivery_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          local.delivery_bucket_arn,
          "${local.delivery_bucket_arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "AllowCloudFrontRead"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${local.delivery_bucket_arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = local.distribution_arns
          }
        }
      },
    ]
  }
}

resource "aws_s3_bucket_policy" "delivery" {
  bucket = local.delivery_bucket_name
  policy = jsonencode(local.delivery_policy)

  lifecycle {
    precondition {
      condition     = length(toset(local.distribution_arns)) == 2
      error_message = "Media delivery requires distinct dev and prod CloudFront distribution ARNs."
    }
  }
}
