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

  environment               = "prod"
  compute                   = "lambda"
  domain_name               = var.domain_name
  subject_alternative_names = ["www.speerd.com"]

  hosted_zone_id = data.terraform_remote_state.global.outputs.hosted_zones[
    "speerd.com"
  ].zone_id

  image_uri = "${data.terraform_remote_state.bootstrap.outputs.prod_ecr_repository_url}@${var.bootstrap_image_digest}"

  media_bucket_regional_domain_name = data.terraform_remote_state.global.outputs.media_delivery_bucket_regional_domain_name

  create_dns_records = true
  private            = false

  secret_parameter_name = var.secret_parameter_name
  alerts_topic_arn      = data.terraform_remote_state.global.outputs.alerts_topic_arn
}
