variable "region" {
  description = "Primary region. Everything regional lives here."
  type        = string
  default     = "us-west-2"
}

variable "github_repository_subject" {
  description = <<-DESC
    GitHub's repository subject prefix, including immutable owner and repository
    IDs. Pinned exactly into every trust policy. A wildcard in a `sub` condition
    on a public repository is the standard critical misconfiguration and must
    never appear.
  DESC
  type        = string
  default     = "potatoHVAC@33634621/portfolio@1343244685"
}

variable "state_bucket_name" {
  description = <<-DESC
    Globally unique S3 bucket holding OpenTofu state. Deliberately does not
    embed the account ID: backend blocks cannot take variables, so this name is
    committed as a literal in backend.tf, and this repository withholds the
    account ID.
  DESC
  type        = string
  default     = "speerd-portfolio-tfstate"
}

variable "dev_image_retention_count" {
  description = <<-DESC
    Commit-tagged images kept in dev/portfolio. Bounds how far back a *first*
    promotion can reach: a SHA older than this window cannot be promoted, and
    images are never rebuilt from a commit because dependencies float. The
    promotion workflow reports "aged out of the retention window" as its own
    failure rather than trying.
  DESC
  type        = number
  default     = 5
}

variable "prod_image_retention_count" {
  description = <<-DESC
    Promoted images kept in prod/portfolio. **This is the rollback set.** ECR
    lifecycle rules cannot see what is deployed, so a low number here can expire
    the image production is running — see the comment in ecr.tf for the exact
    sequence that does it. Raising this is the cheapest possible insurance:
    layers are shared between images, so each extra release costs cents a year.
  DESC
  type        = number
  default     = 5
}
