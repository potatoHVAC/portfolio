variable "environment" {
  description = "Environment name. Suffixes every resource name."
  type        = string
}

variable "compute" {
  description = "Origin substrate. Both environments currently use Lambda."
  type        = string
  default     = "lambda"

  validation {
    condition     = var.compute == "lambda"
    error_message = "Only \"lambda\" is implemented today."
  }
}

variable "domain_name" {
  description = "Primary hostname. Also the certificate's common name."
  type        = string
}

variable "subject_alternative_names" {
  description = "Extra hostnames on the certificate and the distribution."
  type        = list(string)
  default     = []
}

variable "hosted_zone_id" {
  description = "Route 53 zone holding the hostname and the validation records."
  type        = string
}

variable "image_uri" {
  description = "Digest-pinned image. CI moves this afterwards; ignore_changes keeps apply from reverting it."
  type        = string

  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.image_uri))
    error_message = "image_uri must be digest-pinned (repo@sha256:...), never a tag."
  }
}

variable "private" {
  description = "Gate the environment behind edge Basic auth and mark it noindex."
  type        = bool
  default     = false
}

variable "create_dns_records" {
  description = "Create application aliases for the primary hostname and certificate SANs. Certificate validation records are always created."
  type        = bool
  default     = true
}

variable "edge_kvs_arn" {
  description = "KeyValueStore the auth function reads. Required when private."
  type        = string
  default     = null

  validation {
    condition     = !var.private || var.edge_kvs_arn != null
    error_message = "A private environment needs edge_kvs_arn."
  }
}

variable "auth_key" {
  description = "Key holding the expected Authorization header value. Required when private."
  type        = string
  default     = null

  validation {
    condition     = !var.private || var.auth_key != null
    error_message = "A private environment needs auth_key."
  }
}

variable "secret_parameter_name" {
  description = "SSM SecureString the entrypoint reads for SECRET_KEY_BASE."
  type        = string
}

variable "alerts_topic_arn" {
  description = "SNS topic for alarm notifications. Must be in this stack's region."
  type        = string
}

variable "memory_size" {
  description = "Mostly a cold-start setting: Lambda scales CPU with it, and GB-seconds stay roughly flat."
  type        = number
  default     = 1024
}

variable "timeout" {
  type    = number
  default = 30
}

variable "log_retention_days" {
  description = "Lambda logs are the only unbounded cost here."
  type        = number
  default     = 14
}

variable "content_security_policy" {
  description = "Rails sets no CSP, so CloudFront is the only source of one."
  type        = string
  default     = "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'; upgrade-insecure-requests"
}

variable "error_count_threshold" {
  description = "Invocation errors tolerated in a five-minute window before alarming."
  type        = number
  default     = 0
}
