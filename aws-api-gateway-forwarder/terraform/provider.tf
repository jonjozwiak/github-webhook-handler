terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.0"
    }
    // The archive provider is used to download the lambda function zip file
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.6.0"
    }
  }

  required_version = "~> 1.0"
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Application = "Github Webhook Handler"
    }
  }
}
