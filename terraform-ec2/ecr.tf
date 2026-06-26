# terraform/ecr.tf

resource "aws_ecr_repository" "backend_repo" {
  name                 = "<YOUR_PROJECT_NAME>/backend"
  image_tag_mutability = "MUTABLE"
  
  # Highly recommended for development/testing environments. 
  # This allows Terraform to destroy the repo even if it contains images.
  force_delete         = true 

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Environment = "production"
    Project     = "<YOUR_PROJECT_NAME>"
    Service     = "backend"
  }
}

resource "aws_ecr_repository" "nginx_repo" {
  name                 = "<YOUR_PROJECT_NAME>/nginx"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Environment = "production"
    Project     = "<YOUR_PROJECT_NAME>"
    Service     = "nginx"
  }
}

# terraform/ecr.tf (Append this to the bottom)

resource "aws_ecr_lifecycle_policy" "backend_cleanup" {
  repository = aws_ecr_repository.backend_repo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_ecr_lifecycle_policy" "nginx_cleanup" {
  repository = aws_ecr_repository.nginx_repo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}