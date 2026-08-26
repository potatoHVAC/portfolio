resource "aws_route53domains_registered_domain" "public" {
  provider = aws.us_east_1
  for_each = local.public_domains

  domain_name = each.key

  auto_renew         = true
  transfer_lock      = true
  admin_privacy      = true
  billing_privacy    = true
  registrant_privacy = true
  tech_privacy       = true

  # Contact blocks are intentionally omitted. They are computed by the
  # provider, so private contact data stays out of public configuration.
  dynamic "name_server" {
    for_each = sort(aws_route53_zone.public[each.key].name_servers)

    content {
      name = name_server.value
    }
  }
}
