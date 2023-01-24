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

  request.uri = `$${uri.includes(".") ? uri : uri.concat(".html")}`;

  return request;
}
EOF
}
