# Edge configuration for CloudFront Functions, which can read no other AWS
# service. One store serves every environment; keys are namespaced by
# environment name.
#
# Keys are written by hand, never by OpenTofu: `dev-auth` is a credential and
# this repository goes public. See docs/reference/aws-resources.md in `speerd`.
resource "aws_cloudfront_key_value_store" "edge" {
  name    = "portfolio-edge"
  comment = "Portfolio edge configuration. Keys written outside OpenTofu."
}
