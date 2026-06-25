terraform {
  backend "s3" {
    bucket         = "nijine-terraform"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    # Uncomment after running terraform apply once to create the table, then run terraform init -reconfigure
    # dynamodb_table = "nijine-terraform-locks"
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

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "nijine-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

module "site" {
  source       = "github.com/nijine/simple-cf-site"
  domain_name  = "loshakov.link"
  error_object = "404.html"

  default_cache_func_assoc = [{
    event_type   = "viewer-request"
    function_arn = aws_cloudfront_function.rewrite_uri.arn
  }]
}

resource "aws_cloudfront_function" "rewrite_uri" {
  name    = "rewrite-request-if-page-without-dot-html"
  runtime = "cloudfront-js-1.0"
  code    = <<EOF
function handler(event) {
  var request = event.request;
  var uri = request.uri;

  request.uri = `$${uri.includes(".") ? uri : uri === '/' ? uri : uri.concat(".html")}`;

  return request;
}
EOF
}
