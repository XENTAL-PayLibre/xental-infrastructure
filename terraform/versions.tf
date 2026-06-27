terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # Recommended: configure a remote backend (S3 + DynamoDB lock) before apply.
  # backend "s3" {
  #   bucket         = "xental-tfstate"
  #   key            = "infrastructure/terraform.tfstate"
  #   region         = "eu-west-1"
  #   dynamodb_table = "xental-tflock"
  #   encrypt        = true
  # }
}
