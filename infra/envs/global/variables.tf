variable "region" {
  type    = string
  default = "us-west-2"
}

variable "alert_email" {
  description = <<-DESC
    Where budget alerts go. Optional — everything else applies without it.

    **Never commit this.** The repository goes public. Pass it as
    TF_VAR_alert_email, or put it in terraform.tfvars, which is gitignored.
  DESC
  type        = string
  default     = null
}

variable "monthly_budget_usd" {
  type    = string
  default = "20"
}
