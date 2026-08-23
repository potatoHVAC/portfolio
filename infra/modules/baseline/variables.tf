variable "region" {
  description = "Region the trail records. Single-region by design."
  type        = string
}

variable "trail_name" {
  description = "CloudTrail trail name."
  type        = string
  default     = "portfolio-baseline"
}

variable "cloudtrail_bucket_name" {
  description = "Globally unique bucket for trail logs. Carries no account ID."
  type        = string
  default     = "speerd-portfolio-cloudtrail"
}

variable "log_retention_days" {
  description = "Days before trail objects expire. The trail is an audit record for a portfolio site, not a compliance artefact."
  type        = number
  default     = 90
}

variable "monthly_budget_usd" {
  description = <<-DESC
    Monthly cost ceiling that triggers an alert. The design models ~$5/month, so
    this is set well above it: the alarm exists to catch the case where that
    model is wrong, not to track normal variance.
  DESC
  type        = string
  default     = "20"
}

variable "alert_email" {
  description = <<-DESC
    Where budget alerts go. Optional on purpose — the budget notifies the SNS
    topic either way, and the email subscription is the only piece that needs a
    real address. Left null, everything else still applies.

    Never hardcode this: the repository goes public. Supply it as
    TF_VAR_alert_email, or in terraform.tfvars, which is gitignored.
  DESC
  type        = string
  default     = null
}
