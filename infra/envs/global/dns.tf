locals {
  public_domains = toset([
    "speerd.com",
    "speerdrings.com",
  ])

  # ACM chooses among four Amazon CA identifiers at issuance time and does not
  # say which in advance. A CAA record omitting the one it picks fails
  # validation, so all four are listed; every one of them is Amazon, so
  # issuance stays pinned to Amazon either way.
  acm_issuers = [
    "amazon.com",
    "amazontrust.com",
    "awstrust.com",
    "amazonaws.com",
  ]
}

resource "aws_route53_zone" "public" {
  for_each = local.public_domains

  name = each.key
}

# speerd.com only: it is the one domain that receives certificates. With no
# issuewild record, RFC 8659 applies these same identifiers to wildcards.
resource "aws_route53_record" "caa" {
  zone_id = aws_route53_zone.public["speerd.com"].zone_id
  name    = "speerd.com"
  type    = "CAA"
  ttl     = 300

  records = [for issuer in local.acm_issuers : "0 issue \"${issuer}\""]
}
