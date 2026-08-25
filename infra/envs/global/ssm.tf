# The Rails SECRET_KEY_BASE lives at /portfolio/secret_key_base as a
# SecureString under alias/aws/ssm, and is deliberately NOT declared here.
#
# `aws_ssm_parameter` reads its value into state on every refresh, and
# `portfolio-ci` carries ReadOnlyAccess — s3:GetObject on the state bucket
# included. Declaring it would put the secret in plaintext where any pull
# request can read it, defeating the ssm:GetParameter* deny in
# infra/bootstrap/ci-identity.tf that exists to prevent exactly that.
#
# Created and rotated by hand. See the walking skeleton spec, Chunk 9.
