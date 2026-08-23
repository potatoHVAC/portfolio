output "alerts_topic_arn" {
  description = "SNS topic for budget and alarm notifications. Chunks 10 and 12 attach CloudFront alarms to it."
  value       = aws_sns_topic.alerts.arn
}

output "cloudtrail_bucket" {
  value = aws_s3_bucket.trail.id
}

output "email_subscription_pending" {
  description = "True when an email subscription exists but nobody has clicked the confirmation link yet."
  value       = var.alert_email != null
}
