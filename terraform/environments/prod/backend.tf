terraform {
  backend "s3" {
    bucket         = "terraform-state-prod-<ACCOUNT_ID>"
    key            = "eks/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks-prod"
    encrypt        = true
  }
}
