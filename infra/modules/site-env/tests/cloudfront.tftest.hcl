variables {
  environment                       = "dev"
  domain_name                       = "dev.example.com"
  media_bucket_regional_domain_name = "portfolio-media.s3.us-west-2.amazonaws.com"
  hosted_zone_id                    = "Z0123456789EXAMPLE"
  image_uri                         = "123456789012.dkr.ecr.us-west-2.amazonaws.com/dev/portfolio@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  private                           = true
  create_dns_records                = false
  edge_kvs_arn                      = "arn:aws:cloudfront::123456789012:key-value-store/11111111-1111-1111-1111-111111111111"
  auth_key                          = "dev-auth"
  secret_parameter_name             = "/portfolio/secret_key_base"
  alerts_topic_arn                  = "arn:aws:sns:us-west-2:123456789012:portfolio-alerts"
}

mock_provider "aws" {
  alias = "mock"

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-west-2"
    }
  }

  mock_data "aws_kms_alias" {
    defaults = {
      target_key_arn = "arn:aws:kms:us-west-2:123456789012:key/11111111-1111-1111-1111-111111111111"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/portfolio-test-execution"
    }
  }

  mock_resource "aws_cloudfront_function" {
    defaults = {
      arn = "arn:aws:cloudfront::123456789012:function/portfolio-test-viewer-request"
    }
  }

  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn = "arn:aws:cloudfront::123456789012:distribution/EDFDVBD6EXAMPLE"
    }
  }
}

mock_provider "aws" {
  alias = "mock_us_east_1"

  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111"
      domain_validation_options = [
        {
          domain_name           = "dev.example.com"
          resource_record_name  = "_validation.dev.example.com"
          resource_record_type  = "CNAME"
          resource_record_value = "_value.acm-validations.aws"
        }
      ]
    }
  }
}

run "private_media_behavior" {
  command = plan

  providers = {
    aws           = aws.mock
    aws.us_east_1 = aws.mock_us_east_1
  }

  assert {
    condition = (
      aws_cloudfront_origin_access_control.media.origin_access_control_origin_type == "s3" &&
      aws_cloudfront_origin_access_control.media.signing_behavior == "always" &&
      aws_cloudfront_origin_access_control.media.signing_protocol == "sigv4"
    )
    error_message = "The media origin must use always-signed SigV4 S3 OAC."
  }

  assert {
    condition = (
      length(aws_cloudfront_distribution.site.origin) == 2 &&
      one([for origin in aws_cloudfront_distribution.site.origin : origin if origin.origin_id == "media"]).domain_name == var.media_bucket_regional_domain_name &&
      one([for origin in aws_cloudfront_distribution.site.origin : origin if origin.origin_id == "media"]).origin_access_control_id == aws_cloudfront_origin_access_control.media.id
    )
    error_message = "The media origin must target the private delivery bucket through its OAC."
  }

  assert {
    condition = (
      aws_cloudfront_distribution.site.default_cache_behavior[0].target_origin_id == "lambda" &&
      one([for behavior in aws_cloudfront_distribution.site.ordered_cache_behavior : behavior if behavior.path_pattern == "/assets/*"]).target_origin_id == "lambda"
    )
    error_message = "The default and asset behaviours must remain Lambda-backed."
  }

  assert {
    condition = (
      one([for behavior in aws_cloudfront_distribution.site.ordered_cache_behavior : behavior if behavior.path_pattern == "/media/*"]).target_origin_id == "media" &&
      one([for behavior in aws_cloudfront_distribution.site.ordered_cache_behavior : behavior if behavior.path_pattern == "/media/*"]).viewer_protocol_policy == "redirect-to-https" &&
      one([for behavior in aws_cloudfront_distribution.site.ordered_cache_behavior : behavior if behavior.path_pattern == "/media/*"]).compress == true &&
      one([for behavior in aws_cloudfront_distribution.site.ordered_cache_behavior : behavior if behavior.path_pattern == "/media/*"]).allowed_methods == toset(["GET", "HEAD"]) &&
      one([for behavior in aws_cloudfront_distribution.site.ordered_cache_behavior : behavior if behavior.path_pattern == "/media/*"]).cached_methods == toset(["GET", "HEAD"]) &&
      one([for behavior in aws_cloudfront_distribution.site.ordered_cache_behavior : behavior if behavior.path_pattern == "/media/*"]).cache_policy_id == data.aws_cloudfront_cache_policy.optimized.id &&
      one([for behavior in aws_cloudfront_distribution.site.ordered_cache_behavior : behavior if behavior.path_pattern == "/media/*"]).response_headers_policy_id == aws_cloudfront_response_headers_policy.site.id
    )
    error_message = "The media behaviour must retain its GET/HEAD, HTTPS, compression, cache, and response-policy contract."
  }

  assert {
    condition = (
      length(one([for behavior in aws_cloudfront_distribution.site.ordered_cache_behavior : behavior if behavior.path_pattern == "/media/*"]).function_association) == 1 &&
      one(one([for behavior in aws_cloudfront_distribution.site.ordered_cache_behavior : behavior if behavior.path_pattern == "/media/*"]).function_association).event_type == "viewer-request" &&
      one(one([for behavior in aws_cloudfront_distribution.site.ordered_cache_behavior : behavior if behavior.path_pattern == "/media/*"]).function_association).function_arn == aws_cloudfront_function.viewer_request[0].arn
    )
    error_message = "Private environments must retain viewer-request authentication on media."
  }

  assert {
    condition     = output.distribution_arn == aws_cloudfront_distribution.site.arn
    error_message = "The module must export the exact distribution ARN for the media-access policy."
  }
}

run "public_media_behavior" {
  command = plan

  providers = {
    aws           = aws.mock
    aws.us_east_1 = aws.mock_us_east_1
  }

  variables {
    environment = "prod"
    domain_name = "example.com"
    private     = false
  }

  assert {
    condition = (
      length(one([for behavior in aws_cloudfront_distribution.site.ordered_cache_behavior : behavior if behavior.path_pattern == "/media/*"]).function_association) == 0
    )
    error_message = "Public media must not gain a viewer-request function association."
  }
}
