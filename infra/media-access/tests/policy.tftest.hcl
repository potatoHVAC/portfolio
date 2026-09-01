mock_provider "aws" {
  alias = "mock"
}

override_data {
  target = data.terraform_remote_state.global
  values = {
    outputs = {
      media_delivery_bucket_name = "speerd-portfolio-media-123456789012-us-west-2"
      media_delivery_bucket_arn  = "arn:aws:s3:::speerd-portfolio-media-123456789012-us-west-2"
    }
  }
}

override_data {
  target = data.terraform_remote_state.dev
  values = {
    outputs = {
      distribution_arn = "arn:aws:cloudfront::123456789012:distribution/EDEVEXAMPLE"
    }
  }
}

override_data {
  target = data.terraform_remote_state.prod
  values = {
    outputs = {
      distribution_arn = "arn:aws:cloudfront::123456789012:distribution/EPRODEXAMPLE"
    }
  }
}

run "exact_cloudfront_delivery_policy" {
  command = plan

  providers = {
    aws = aws.mock
  }

  assert {
    condition     = aws_s3_bucket_policy.delivery.bucket == "speerd-portfolio-media-123456789012-us-west-2"
    error_message = "The policy must attach only to the delivery bucket."
  }

  assert {
    condition = (
      one([
        for statement in jsondecode(aws_s3_bucket_policy.delivery.policy).Statement :
        statement if statement.Sid == "DenyInsecureTransport"
      ]).Effect == "Deny" &&
      one([
        for statement in jsondecode(aws_s3_bucket_policy.delivery.policy).Statement :
        statement if statement.Sid == "DenyInsecureTransport"
      ]).Principal == "*" &&
      one([
        for statement in jsondecode(aws_s3_bucket_policy.delivery.policy).Statement :
        statement if statement.Sid == "DenyInsecureTransport"
      ]).Action == "s3:*" &&
      toset(one([
        for statement in jsondecode(aws_s3_bucket_policy.delivery.policy).Statement :
        statement if statement.Sid == "DenyInsecureTransport"
        ]).Resource) == toset([
        "arn:aws:s3:::speerd-portfolio-media-123456789012-us-west-2",
        "arn:aws:s3:::speerd-portfolio-media-123456789012-us-west-2/*",
      ]) &&
      one([
        for statement in jsondecode(aws_s3_bucket_policy.delivery.policy).Statement :
        statement if statement.Sid == "DenyInsecureTransport"
      ]).Condition.Bool["aws:SecureTransport"] == "false"
    )
    error_message = "The complete delivery policy must deny every non-TLS bucket and object request."
  }

  assert {
    condition = (
      one([
        for statement in jsondecode(aws_s3_bucket_policy.delivery.policy).Statement :
        statement if statement.Sid == "AllowCloudFrontRead"
      ]).Effect == "Allow" &&
      one([
        for statement in jsondecode(aws_s3_bucket_policy.delivery.policy).Statement :
        statement if statement.Sid == "AllowCloudFrontRead"
      ]).Principal.Service == "cloudfront.amazonaws.com" &&
      one([
        for statement in jsondecode(aws_s3_bucket_policy.delivery.policy).Statement :
        statement if statement.Sid == "AllowCloudFrontRead"
      ]).Action == "s3:GetObject" &&
      one([
        for statement in jsondecode(aws_s3_bucket_policy.delivery.policy).Statement :
        statement if statement.Sid == "AllowCloudFrontRead"
      ]).Resource == "arn:aws:s3:::speerd-portfolio-media-123456789012-us-west-2/*"
    )
    error_message = "Only CloudFront may read delivery-bucket objects."
  }

  assert {
    condition = (
      toset(one([
        for statement in jsondecode(aws_s3_bucket_policy.delivery.policy).Statement :
        statement if statement.Sid == "AllowCloudFrontRead"
        ]).Condition.StringEquals["AWS:SourceArn"]) == toset([
        "arn:aws:cloudfront::123456789012:distribution/EDEVEXAMPLE",
        "arn:aws:cloudfront::123456789012:distribution/EPRODEXAMPLE",
      ]) &&
      alltrue([
        for arn in one([
          for statement in jsondecode(aws_s3_bucket_policy.delivery.policy).Statement :
          statement if statement.Sid == "AllowCloudFrontRead"
        ]).Condition.StringEquals["AWS:SourceArn"] : !strcontains(arn, "*")
      ])
    )
    error_message = "CloudFront reads must require both exact distribution ARNs without wildcards."
  }

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.delivery.policy).Statement) == 2
    error_message = "The delivery policy may contain only TLS denial and exact CloudFront read statements."
  }

  assert {
    condition     = !strcontains(aws_s3_bucket_policy.delivery.policy, "originals")
    error_message = "The media-access state must never grant access to the originals bucket."
  }
}
