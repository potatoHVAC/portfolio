module "baseline" {
  source = "../../modules/baseline"

  region             = var.region
  alert_email        = var.alert_email
  monthly_budget_usd = var.monthly_budget_usd
}

data "aws_caller_identity" "current" {}

module "media_storage" {
  source = "../../modules/media-storage"

  account_id = data.aws_caller_identity.current.account_id
  region     = var.region
}
