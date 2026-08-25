terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "speerd-portfolio"
      Stack     = "dev"
      ManagedBy = "OpenTofu"
    }
  }
}

# The ACM certificate only. CloudFront accepts certificates from no other
# region; every other resource in this stack is us-west-2.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "speerd-portfolio"
      Stack     = "dev"
      ManagedBy = "OpenTofu"
    }
  }
}
