output "distribution_id" {
  value = aws_cloudfront_distribution.site.id
}

output "distribution_domain_name" {
  description = "Reachable before DNS points anywhere. How an environment is verified pre-cutover."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "distribution_arn" {
  description = "Exact distribution ARN used by the media bucket access policy."
  value       = aws_cloudfront_distribution.site.arn
}

output "function_name" {
  description = "What CI calls update-function-code against."
  value       = aws_lambda_function.site.function_name
}

output "function_url" {
  description = "Must return 403 when called directly. If it ever serves a page, the privacy gate is bypassed."
  value       = aws_lambda_function_url.live.function_url
}

output "site_url" {
  value = "https://${var.domain_name}"
}
