variable "region" {
  type    = string
  default = "us-west-2"
}

variable "domain_name" {
  type    = string
  default = "speerd.com"
}

variable "bootstrap_image_digest" {
  description = <<-DESC
    The first digest promoted into prod/portfolio. Promotion moves the Lambda
    alias afterwards and ignore_changes keeps apply from moving it back.
  DESC
  type        = string
  default     = "sha256:0058c56231ea3e49374e6905d12304f7484ea9634cbb2d657bccdd0c5fb3ff45"
}

variable "secret_parameter_name" {
  type    = string
  default = "/portfolio/secret_key_base"
}
