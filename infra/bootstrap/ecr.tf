# Two repositories, not one with tag conventions. The production repository's
# contents then are a complete, self-evident record of what has ever been
# production, and the dev deploy role has no write path into it.

resource "aws_ecr_repository" "dev" {
  name = "dev/portfolio"

  # MUTABLE because the `main` tag has to move onto each new build. Nothing
  # running ever references it — deployments resolve a digest first.
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "dev" {
  repository = aws_ecr_repository.dev.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the 5 most recent commit-tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["git-"]
          countType     = "imageCountMoreThan"
          countNumber   = var.dev_image_retention_count
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Expire untagged layers after a day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
    ]
  })
}

resource "aws_ecr_repository" "prod" {
  name = "prod/portfolio"

  # IMMUTABLE: a promoted git-<sha> tag can never be repointed, so production is
  # pinned to bytes by name as well as by digest. Re-promoting a SHA already
  # present therefore fails the copy — the promotion workflow checks first and
  # treats "already there at the same digest" as success.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Retention on prod/portfolio, added 2026-08-22 at the owner's request to cap
# cost. This reverses the original "no expiry here" decision, and the reason for
# that decision has not gone away — it is written out below rather than dropped.
#
# ECR lifecycle rules cannot see what is deployed. They count images and delete
# the oldest, whether or not App Runner is running one of them.
#
# The reachable failure, precisely: promote five releases, roll production back
# to the oldest, then promote once more. That sixth promotion pushes the count
# past the limit and the oldest image — the one production is *currently
# running* — is expired. Nothing breaks at that moment, because App Runner has
# already pulled it. It breaks later, at the next instance replacement, deploy,
# or scale event, when the pull fails. A latent outage with no obvious cause and
# a long delay between action and symptom.
#
# Two mitigations, neither of them the rule below:
#   - Rolling back is a promotion. Promote the old SHA rather than pointing the
#     service at it, and the image is re-copied and becomes the newest again.
#   - A retention job that reads the deployed digest first and skips it is the
#     correct fix, and is what the design's Future development section describes.
resource "aws_ecr_lifecycle_policy" "prod" {
  repository = aws_ecr_repository.prod.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the ${var.prod_image_retention_count} most recent promoted images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["git-"]
          countType     = "imageCountMoreThan"
          countNumber   = var.prod_image_retention_count
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Expire untagged layers after a day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
    ]
  })
}
