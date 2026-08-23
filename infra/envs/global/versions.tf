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
      Stack     = "global"
      ManagedBy = "OpenTofu"
    }
  }
}

# ACM certificates for CloudFront and the Route 53 Domains API are us-east-1
# only. Unused in this stack today; declared so every stack has one shape.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "speerd-portfolio"
      Stack     = "global"
      ManagedBy = "OpenTofu"
    }
  }
}
