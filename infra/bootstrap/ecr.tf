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
        description  = "Keep the 20 most recent commit-tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["git-"]
          countType     = "imageCountMoreThan"
          countNumber   = 20
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

# Deliberately NO lifecycle policy on prod/portfolio. Only promoted images land
# here and they are the rollback set; a count or age rule would eventually
# delete the image production is running, or the one you would roll back to.
# Retention here cannot be decided until the rollback strategy is — see the
# design's Future development section.
