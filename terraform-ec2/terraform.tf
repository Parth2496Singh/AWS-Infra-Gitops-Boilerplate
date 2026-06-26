terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  backend "s3" {
    bucket = "my-project-terraform-state-bucket"
    region = "us-east-1"
    key = "terraform.tfstate"
    dynamodb_table = "my-project-terraform-lock-table"
    
  }
}