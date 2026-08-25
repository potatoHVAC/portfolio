locals {
  origin_id = var.compute

  # https://<id>.lambda-url.<region>.on.aws/ -> host only
  origin_domain_name = trimsuffix(trimprefix(aws_lambda_function_url.live.function_url, "https://"), "/")

  aliases = concat([var.domain_name], var.subject_alternative_names)
}

# Managed policies rather than hand-rolled ones: AWS maintains them and the
# names are stable.
data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

# Host and Authorization must both be withheld from the origin.
#
# OAC signs each request with SigV4 and carries the signature in Authorization,
# so forwarding the viewer's own Authorization overwrites it and the function
# URL answers 403 without ever invoking the function. Host is excluded for the
# same reason: the signature covers the origin's host, not the viewer's.
#
# Managed-AllViewerExceptHostHeader forwards Authorization, so it cannot be
# used with OAC. Withholding it also keeps the edge credential out of Rails.
resource "aws_cloudfront_origin_request_policy" "site" {
  name    = local.name
  comment = "All viewer headers except Host and Authorization, which OAC owns."

  headers_config {
    header_behavior = "allExcept"

    headers {
      items = ["host", "authorization"]
    }
  }

  cookies_config {
    cookie_behavior = "all"
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}

resource "aws_cloudfront_origin_access_control" "lambda" {
  name                              = "${local.name}-lambda"
  description                       = "Signs CloudFront's requests to the ${var.environment} function URL."
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "viewer_request" {
  count = var.private ? 1 : 0

  name    = "${local.name}-viewer-request"
  runtime = "cloudfront-js-2.0"
  comment = "Basic auth gate for ${var.domain_name}."
  publish = true

  key_value_store_associations = [var.edge_kvs_arn]

  code = templatefile("${path.module}/functions/viewer-request.js", {
    auth_key = var.auth_key
    realm    = "portfolio ${var.environment}"
  })
}

resource "aws_cloudfront_response_headers_policy" "site" {
  name    = local.name
  comment = "Security headers for ${var.domain_name}."

  security_headers_config {
    # override: Rails sets its own HSTS under force_ssl. One header, ours.
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = false
      override                   = true
    }

    content_security_policy {
      content_security_policy = var.content_security_policy
      override                = true
    }

    content_type_options {
      override = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }

  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      value    = "accelerometer=(), camera=(), display-capture=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()"
      override = true
    }

    dynamic "items" {
      for_each = var.private ? [1] : []

      content {
        header = "X-Robots-Tag"
        value  = "noindex, nofollow"
        # false: the function already sets this on its 401, and that value wins.
        override = false
      }
    }
  }
}

resource "aws_cloudfront_distribution" "site" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "portfolio ${var.environment}"
  aliases         = local.aliases
  http_version    = "http2and3"

  # North America and Europe. The cheapest class; a portfolio does not need
  # edge presence in every region.
  price_class = "PriceClass_100"

  origin {
    domain_name              = local.origin_domain_name
    origin_id                = local.origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.lambda.id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Caching disabled on the page itself. Rails sends no Cache-Control on HTML,
  # so a caching policy would hold it for the policy default of 24 hours and a
  # merge would not reach the environment until it expired.
  default_cache_behavior {
    target_origin_id       = local.origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id            = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.site.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.site.id

    dynamic "function_association" {
      for_each = var.private ? [1] : []

      content {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.viewer_request[0].arn
      }
    }
  }

  # Digest-stamped by the asset pipeline and served with a one-year max-age.
  ordered_cache_behavior {
    path_pattern           = "/assets/*"
    target_origin_id       = local.origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id            = data.aws_cloudfront_cache_policy.optimized.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.site.id

    dynamic "function_association" {
      for_each = var.private ? [1] : []

      content {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.viewer_request[0].arn
      }
    }
  }

  # Nothing serves /media/* yet. It exists now so the media pipeline attaches to
  # an existing behaviour instead of reshaping the cache policy later.
  ordered_cache_behavior {
    path_pattern           = "/media/*"
    target_origin_id       = local.origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id            = data.aws_cloudfront_cache_policy.optimized.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.site.id

    dynamic "function_association" {
      for_each = var.private ? [1] : []

      content {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.viewer_request[0].arn
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.site.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}
