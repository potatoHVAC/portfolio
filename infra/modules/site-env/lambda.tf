data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# The AWS-managed SSM key. Free, where a customer-managed key would be $1/mo.
data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}

locals {
  name = "portfolio-${var.environment}"

  secret_parameter_arn = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter${var.secret_parameter_name}"
}

data "aws_iam_policy_document" "execution_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${local.name}-execution"
  description        = "Runtime role for the ${var.environment} site function."
  assume_role_policy = data.aws_iam_policy_document.execution_assume.json
}

# Created here rather than by Lambda on first invoke, so retention is bounded
# from the start instead of defaulting to never expire.
resource "aws_cloudwatch_log_group" "site" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "execution" {
  statement {
    sid       = "WriteOwnLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.site.arn}:*"]
  }

  statement {
    sid       = "ReadAppSecret"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = [local.secret_parameter_arn]
  }

  # The managed key is shared across the account's SSM parameters, so the grant
  # is narrowed to decryption performed on SSM's behalf.
  statement {
    sid       = "DecryptAppSecret"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [data.aws_kms_alias.ssm.target_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${data.aws_region.current.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "runtime"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}

resource "aws_lambda_function" "site" {
  function_name = local.name
  role          = aws_iam_role.execution.arn
  package_type  = "Image"
  image_uri     = var.image_uri
  architectures = ["arm64"]
  memory_size   = var.memory_size
  timeout       = var.timeout
  publish       = true

  # Also baked into the image. Set here so the IAM grant above and the path the
  # entrypoint actually reads cannot drift apart.
  environment {
    variables = {
      SECRET_KEY_BASE_PARAMETER = var.secret_parameter_name
    }
  }

  depends_on = [
    aws_iam_role_policy.execution,
    aws_cloudwatch_log_group.site,
  ]

  # CI moves this on every deploy. Without it the next apply reverts the
  # environment to the bootstrap digest.
  lifecycle {
    ignore_changes = [image_uri]
  }
}

resource "aws_lambda_alias" "live" {
  name             = "live"
  description      = "What the distribution invokes. CI moves it; apply must not."
  function_name    = aws_lambda_function.site.function_name
  function_version = aws_lambda_function.site.version

  lifecycle {
    ignore_changes = [function_version]
  }
}

# AWS_IAM is load-bearing. The privacy gate is a CloudFront Function, so
# anything reaching this URL directly bypasses it. NONE would publish the
# environment to anyone who learns the address, with no visible symptom.
resource "aws_lambda_function_url" "live" {
  function_name      = aws_lambda_function.site.function_name
  qualifier          = aws_lambda_alias.live.name
  authorization_type = "AWS_IAM"
  invoke_mode        = "BUFFERED"
}

resource "aws_lambda_permission" "cloudfront" {
  statement_id           = "AllowCloudFrontInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.site.function_name
  qualifier              = aws_lambda_alias.live.name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.site.arn
  function_url_auth_type = "AWS_IAM"
}

# Two permissions, not one. Function URLs created after October 2025 also check
# lambda:InvokeFunction, and CloudFront gets a bare 403 with no indication of
# which one is missing when only InvokeFunctionUrl is present.
resource "aws_lambda_permission" "cloudfront_invoke_function" {
  statement_id  = "AllowCloudFrontInvokeFunction"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.site.function_name
  qualifier     = aws_lambda_alias.live.name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = aws_cloudfront_distribution.site.arn
}
