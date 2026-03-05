terraform {
  backend "s3" {
    bucket         = "terraform-state-staging-<ACCOUNT_ID>"
    key            = "eks/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks-staging"
    encrypt        = true
  }
}
