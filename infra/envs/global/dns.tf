locals {
  public_domains = toset([
    "speerd.com",
    "speerdrings.com",
  ])
}

resource "aws_route53_zone" "public" {
  for_each = local.public_domains

  name = each.key
}
