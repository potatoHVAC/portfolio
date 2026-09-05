# Adding an image here is the only place a new one has to be declared.
locals {
  dev_images = {
    # tag_prefix is what retention keys off, so an image whose tags do not carry
    # it accumulates forever.
    "portfolio"       = { tag_prefix = "git-" }  # the Rails application image
    "portfolio-media" = { tag_prefix = "tool-" } # the media build tool, tagged by content hash
  }
}

resource "aws_ecr_repository" "dev" {
  for_each = local.dev_images

  name = "dev/${each.key}"

  # MUTABLE: the `main` tag has to move onto each new build.
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "dev" {
  for_each = local.dev_images

  repository = aws_ecr_repository.dev[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the ${var.dev_image_retention_count} most recent ${each.value.tag_prefix} images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = [each.value.tag_prefix]
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

# dev/portfolio predates the for_each above. Without these, the renamed state
# address plans as destroy-and-create, deleting the repository and its images.
moved {
  from = aws_ecr_repository.dev
  to   = aws_ecr_repository.dev["portfolio"]
}

moved {
  from = aws_ecr_lifecycle_policy.dev
  to   = aws_ecr_lifecycle_policy.dev["portfolio"]
}

resource "aws_ecr_repository" "prod" {
  name = "prod/portfolio"

  # IMMUTABLE: re-promoting a SHA already present fails the copy, so the
  # promotion workflow checks first and treats a matching digest as success.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# A digest that ages out of ECR cannot be promoted again by commit SHA, even
# though the Lambda version still runs it. Five images is the rollback window.
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
