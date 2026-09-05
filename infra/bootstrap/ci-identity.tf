# GitHub OIDC, and three roles separated by what they may reach. No long-lived
# AWS keys in GitHub.
#
# The split is the point: the workflow that runs on every merge has no IAM path
# to production. `dev-deploy` cannot write prod/portfolio or update the
# production function. That is a property of these policies,
# not of workflow discipline.
#
# `tofu apply` is NOT a CI action. Infrastructure is applied by a human with the
# `steep` credentials; CI plans and deploys images. There is deliberately no
# apply role here.

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  sub_prefix = "repo:${var.github_repository_subject}"

  # These resources arrive in Chunks 10 and 12. The ARNs
  # are constructed rather than deferred so the roles are narrow from the first
  # apply, never widened-then-tightened.
  dev_function_arn  = "arn:aws:lambda:${var.region}:${local.account_id}:function:portfolio-dev"
  prod_function_arn = "arn:aws:lambda:${var.region}:${local.account_id}:function:portfolio-prod"

  secret_parameter_arn = "arn:aws:ssm:${var.region}:${local.account_id}:parameter/portfolio/*"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

# --- trust policies -------------------------------------------------------
# Every `sub` is an exact string. StringEquals with a list is an OR of exact
# matches, which is what allows two refs without reaching for StringLike.

data "aws_iam_policy_document" "trust_ci" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "${local.sub_prefix}:pull_request",
        "${local.sub_prefix}:ref:refs/heads/main",
      ]
    }
  }
}

data "aws_iam_policy_document" "trust_dev_deploy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.sub_prefix}:ref:refs/heads/main"]
    }
  }
}

data "aws_iam_policy_document" "trust_prod_deploy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # The GitHub Environment, not a branch. Approval is then enforced by the
    # trust policy as well as by the workflow.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.sub_prefix}:environment:production"]
    }
  }
}

# --- ci: read-only plan role ----------------------------------------------

resource "aws_iam_role" "ci" {
  name               = "portfolio-ci"
  description        = "Read-only. Assumed on pull requests and pushes to main for tofu plan."
  assume_role_policy = data.aws_iam_policy_document.trust_ci.json
}

# ReadOnlyAccess rather than a hand-rolled list across a dozen services: the
# hand-rolled version breaks every time the stack gains a service, and the
# failure mode is a confusing plan rather than a security event.
resource "aws_iam_role_policy_attachment" "ci_readonly" {
  role       = aws_iam_role.ci.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "ci_guardrails" {
  # ReadOnlyAccess grants ssm:Get*, so the app secret is fenced off explicitly.
  # SecureString values are already protected by the absent kms:Decrypt, but a
  # parameter created as a plain String by mistake should not be readable by a
  # role that any pull request can assume.
  statement {
    sid       = "DenyAppSecretReads"
    effect    = "Deny"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = [local.secret_parameter_arn]
  }
}

resource "aws_iam_role_policy" "ci_guardrails" {
  name   = "guardrails"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci_guardrails.json
}

# --- dev-deploy -----------------------------------------------------------

resource "aws_iam_role" "dev_deploy" {
  name               = "portfolio-dev-deploy"
  description        = "Push to dev/portfolio and deploy the dev function. No path to production."
  assume_role_policy = data.aws_iam_policy_document.trust_dev_deploy.json
}

data "aws_iam_policy_document" "dev_deploy" {
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this action does not support resource scoping
  }

  statement {
    sid    = "PushDevImages"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:ListImages",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    # Every dev repository by name; * would let a future consumer in this
    # account overwrite these images.
    resources = [for repository in aws_ecr_repository.dev : repository.arn]
  }

  statement {
    sid    = "DeployDevFunction"
    effect = "Allow"
    actions = [
      "lambda:GetAlias",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:PublishVersion",
      "lambda:UpdateAlias",
      "lambda:UpdateFunctionCode",
    ]
    resources = [local.dev_function_arn, "${local.dev_function_arn}:*"]
  }
}

resource "aws_iam_role_policy" "dev_deploy" {
  name   = "deploy"
  role   = aws_iam_role.dev_deploy.id
  policy = data.aws_iam_policy_document.dev_deploy.json
}

# --- prod-deploy ----------------------------------------------------------

resource "aws_iam_role" "prod_deploy" {
  name               = "portfolio-prod-deploy"
  description        = "Copy a dev image into prod/portfolio and deploy it. Manual dispatch only."
  assume_role_policy = data.aws_iam_policy_document.trust_prod_deploy.json
}

data "aws_iam_policy_document" "prod_deploy" {
  statement {
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Read only, on the dev side. GetDownloadUrlForLayer is what lets skopeo pull
  # the layers it copies.
  statement {
    sid    = "ReadDevImages"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:ListImages",
    ]
    # The application image only; tool images are never promoted.
    resources = [aws_ecr_repository.dev["portfolio"].arn]
  }

  statement {
    sid    = "WriteProdImages"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:ListImages",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.prod.arn]
  }

  statement {
    sid    = "DeployProdFunction"
    effect = "Allow"
    actions = [
      "lambda:GetAlias",
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:PublishVersion",
      "lambda:UpdateAlias",
      "lambda:UpdateFunctionCode",
    ]
    resources = [local.prod_function_arn, "${local.prod_function_arn}:*"]
  }
}

resource "aws_iam_role_policy" "prod_deploy" {
  name   = "deploy"
  role   = aws_iam_role.prod_deploy.id
  policy = data.aws_iam_policy_document.prod_deploy.json
}
