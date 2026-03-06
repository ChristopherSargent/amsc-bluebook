aws_region       = "us-east-1"
environment      = "prod"
cluster_name     = "eks-prod"
cluster_version  = "1.30"

gitlab_url          = "https://gitlab.com"
config_repo_path    = "my-org/amsc-bluebook"  # update me — path to THIS repo in GitLab
gitlab_project_path = "my-org/my-app"        # update me

ecr_repositories = [
  "myapp/backend",
  "myapp/frontend",
]

cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"] # replace with CI runner / VPN CIDRs

letsencrypt_email = "platform@example.com" # update me — used for Let's Encrypt cert expiry notifications
