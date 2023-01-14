terraform {
  backend "s3" {
    bucket = "nijine-terraform"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.49"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-east-1"
}

module "site" {
  source       = "github.com/nijine/simple-cf-site"
  domain_name  = "loshakov.link"
  error_object = "404.html"
}
