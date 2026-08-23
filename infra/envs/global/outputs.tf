output "alerts_topic_arn" {
  description = "Attach CloudFront alarms here in Chunks 10 and 12."
  value       = module.baseline.alerts_topic_arn
}

output "cloudtrail_bucket" {
  value = module.baseline.cloudtrail_bucket
}

output "hosted_zones" {
  description = "Route 53 hosted zones and the registrar nameservers for each domain."
  value = {
    for domain, zone in aws_route53_zone.public : domain => {
      zone_id      = zone.zone_id
      name_servers = zone.name_servers
    }
  }
}
