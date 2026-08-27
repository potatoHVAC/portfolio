# ALIAS, not CNAME: the apex cannot hold a CNAME, and the same shape works for
# a subdomain. Z2FDTNDATAQYW2 is CloudFront's fixed hosted zone id.
resource "aws_route53_record" "site" {
  for_each = var.create_dns_records ? toset(["A", "AAAA"]) : toset([])

  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = each.key

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "site_alternative" {
  for_each = var.create_dns_records ? {
    for pair in setproduct(toset(var.subject_alternative_names), toset(["A", "AAAA"])) : "${pair[0]}:${pair[1]}" => {
      name = pair[0]
      type = pair[1]
    }
  } : {}

  zone_id = var.hosted_zone_id
  name    = each.value.name
  type    = each.value.type

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}
