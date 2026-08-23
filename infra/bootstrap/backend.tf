# Not present during the very first apply — see README.md. Backend blocks cannot
# reference variables, so the bucket name is a literal and must match
# var.state_bucket_name.
terraform {
  backend "s3" {
    bucket       = "speerd-portfolio-tfstate"
    key          = "bootstrap/terraform.tfstate"
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true
  }
}
