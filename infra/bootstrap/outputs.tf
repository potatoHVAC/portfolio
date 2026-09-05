# These become GitHub repository variables — AWS_CI_ROLE_ARN,
# AWS_DEV_DEPLOY_ROLE_ARN, AWS_PROD_DEPLOY_ROLE_ARN. They carry the account ID,
# so they belong in GitHub's settings and the Actions log, never in a pull
# request comment.

output "state_bucket" {
  description = "S3 bucket holding OpenTofu state for every stack."
  value       = aws_s3_bucket.state.id
}

output "ci_role_arn" {
  description = "Read-only plan role. Assumed on pull requests and main."
  value       = aws_iam_role.ci.arn
}

output "dev_deploy_role_arn" {
  description = "Pushes dev images and moves the dev alias."
  value       = aws_iam_role.dev_deploy.arn
}

output "prod_deploy_role_arn" {
  description = "Promotes an image into production."
  value       = aws_iam_role.prod_deploy.arn
}

output "dev_ecr_repository_urls" {
  description = "Registry URL per dev image, keyed by image name."
  value       = { for name, repository in aws_ecr_repository.dev : name => repository.repository_url }
}

output "prod_ecr_repository_url" {
  value = aws_ecr_repository.prod.repository_url
}
