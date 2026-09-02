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

output "edge_key_value_store_arn" {
  description = "CloudFront Functions attach to this store to read their configuration."
  value       = aws_cloudfront_key_value_store.edge.arn
}

output "media_originals_bucket_name" {
  description = "Private, versioned archive for unchanged portfolio source media."
  value       = module.media_storage.originals_bucket_name
}

output "media_originals_bucket_arn" {
  description = "ARN of the private portfolio source-media archive."
  value       = module.media_storage.originals_bucket_arn
}

output "media_delivery_bucket_name" {
  description = "Private origin bucket for content-addressed portfolio derivatives."
  value       = module.media_storage.delivery_bucket_name
}

output "media_delivery_bucket_arn" {
  description = "ARN of the private portfolio derivative bucket."
  value       = module.media_storage.delivery_bucket_arn
}

output "media_delivery_bucket_regional_domain_name" {
  description = "Regional S3 domain consumed by the portfolio CloudFront origins."
  value       = module.media_storage.delivery_bucket_regional_domain_name
}
