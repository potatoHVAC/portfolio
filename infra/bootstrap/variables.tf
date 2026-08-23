variable "region" {
  description = "Primary region. Everything regional lives here."
  type        = string
  default     = "us-west-2"
}

variable "github_repository" {
  description = <<-DESC
    owner/name of the GitHub repository allowed to assume the CI roles. Pinned
    exactly into every trust policy. A wildcard in a `sub` condition on a public
    repository is the standard critical misconfiguration and must never appear.
  DESC
  type        = string
  default     = "potatoHVAC/portfolio"
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
