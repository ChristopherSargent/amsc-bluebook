# Run `terraform/bootstrap/main.tf` first to create this bucket and table.
# Then run: terraform init
terraform {
  backend "s3" {
    # Fill in after running bootstrap
    bucket         = "terraform-state-dev-<ACCOUNT_ID>"
    key            = "eks/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks-dev"
    encrypt        = true
  }
}
