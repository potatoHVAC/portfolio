module "baseline" {
  source = "../../modules/baseline"

  region             = var.region
  alert_email        = var.alert_email
  monthly_budget_usd = var.monthly_budget_usd
}
