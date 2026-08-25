terraform {
  backend "s3" {
    bucket       = "speerd-portfolio-tfstate"
    key          = "dev/terraform.tfstate"
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true
  }
}
