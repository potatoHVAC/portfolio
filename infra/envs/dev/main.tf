data "terraform_remote_state" "bootstrap" {
  backend = "s3"

  config = {
    bucket = "speerd-portfolio-tfstate"
    key    = "bootstrap/terraform.tfstate"
    region = "us-west-2"
  }
}

data "terraform_remote_state" "global" {
  backend = "s3"

  config = {
    bucket = "speerd-portfolio-tfstate"
    key    = "global/terraform.tfstate"
    region = "us-west-2"
  }
}

module "site" {
  source = "../../modules/site-env"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  environment = "dev"
  compute     = "lambda"
  domain_name = var.domain_name

  hosted_zone_id = data.terraform_remote_state.global.outputs.hosted_zones[
    "speerd.com"
  ].zone_id

  image_uri = "${data.terraform_remote_state.bootstrap.outputs.dev_ecr_repository_url}@${var.bootstrap_image_digest}"

  # Not public: Basic auth at the edge and noindex on every response.
  private      = true
  edge_kvs_arn = data.terraform_remote_state.global.outputs.edge_key_value_store_arn
  auth_key     = var.auth_key

  secret_parameter_name = var.secret_parameter_name
  alerts_topic_arn      = data.terraform_remote_state.global.outputs.alerts_topic_arn
}
