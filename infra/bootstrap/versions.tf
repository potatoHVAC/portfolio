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
      Stack     = "bootstrap"
      ManagedBy = "OpenTofu"
    }
  }
}

# Declared here, unused here. ACM certificates for CloudFront and the Route 53
# Domains API are us-east-1 only, so every environment carries this alias; the
# shape is identical across stacks on purpose.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "speerd-portfolio"
      Stack     = "bootstrap"
      ManagedBy = "OpenTofu"
    }
  }
}
