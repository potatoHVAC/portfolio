variable "region" {
  type    = string
  default = "us-west-2"
}

variable "domain_name" {
  type    = string
  default = "dev.speerd.com"
}

variable "bootstrap_image_digest" {
  description = <<-DESC
    The image this environment is created from. CI moves the function off it on
    the next merge and ignore_changes keeps apply from moving it back, so this
    matters only at creation.

    Defaults to the image published by the `main` run for 53ee101.
  DESC
  type        = string
  default     = "sha256:fa991bd9ef1d1617f3a260e0d0e64f620ad6073e6ec527c1100f49d759ca3dd1"
}

variable "secret_parameter_name" {
  type    = string
  default = "/portfolio/secret_key_base"
}

variable "auth_key" {
  description = "KeyValueStore key holding the expected Authorization header."
  type        = string
  default     = "dev-auth"
}
