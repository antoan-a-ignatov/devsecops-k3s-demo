terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.51.0"
    }
  }

  backend "s3" {
    bucket = "devsecops-k3s-demo-tfstate-antoan"
    key    = "k3s-demo/terraform.tfstate"
    region = "eu-north-1"
  }
}

provider "aws" {
  region = "eu-north-1"
}
