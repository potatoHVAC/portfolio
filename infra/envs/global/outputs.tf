output "alerts_topic_arn" {
  description = "Attach CloudFront alarms here in Chunks 10 and 12."
  value       = module.baseline.alerts_topic_arn
}

output "cloudtrail_bucket" {
  value = module.baseline.cloudtrail_bucket
}
