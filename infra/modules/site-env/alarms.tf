# us-west-2, on the function's own error count.
#
# CloudFront's 5xxErrorRate would be the broader signal, but that metric is
# published only in us-east-1 and an alarm can notify only a topic in its own
# region — so it would need a second SNS topic there. This catches what
# actually breaks on a one-page site: a Rails 500, a failed boot, an SSM read
# that returns nothing.
resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${local.name}-errors"
  alarm_description   = "Invocation errors on ${local.name}. Any error is signal at this traffic level."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.error_count_threshold
  comparison_operator = "GreaterThanThreshold"

  # An idle environment publishes no data points; that is not a fault.
  treat_missing_data = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.site.function_name
  }

  alarm_actions = [var.alerts_topic_arn]
  ok_actions    = [var.alerts_topic_arn]
}
