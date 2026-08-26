# A cost ceiling. The design models a low-traffic serverless site; this catches
# a runaway CloudFront bill, invocation spike, or service left after an experiment.
#
# The first two budgets are free.

resource "aws_sns_topic" "alerts" {
  name = "portfolio-alerts"
}

data "aws_iam_policy_document" "alerts" {
  # Budgets publishes cross-service, so the topic must name it explicitly. The
  # SourceAccount condition is what stops any other account's budget from
  # publishing here.
  statement {
    sid       = "AllowBudgetsPublish"
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid       = "AllowCloudWatchAlarmsPublish"
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.alerts.json
}

# Optional on purpose. The budget notifies the topic either way; this is the
# only resource that needs a real address, and the address must never be
# committed — the repository goes public.
#
# OpenTofu creates this in `pending confirmation` and a human clicks the link in
# the resulting email. That is expected, not drift: a later plan will still show
# no changes, but no mail arrives until it is confirmed.
resource "aws_sns_topic_subscription" "alerts_email" {
  count = var.alert_email == null ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_budgets_budget" "monthly" {
  name         = "portfolio-monthly"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Actual spend crossing most of the ceiling: something is already wrong.
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }

  # Forecast crossing the whole ceiling: the month is trending wrong even if
  # today's number looks fine. This is the one that gives useful warning.
  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.alerts.arn]
  }

  depends_on = [aws_sns_topic_policy.alerts]
}
