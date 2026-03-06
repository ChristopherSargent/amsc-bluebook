aws_region       = "us-east-1"
environment      = "dev"
cluster_name     = "eks-dev"
cluster_version  = "1.32"

gitlab_url          = "https://gitlab.com"
config_repo_path    = "my-org/amsc-bluebook"  # update me — path to THIS repo in GitLab
gitlab_project_path = "my-org/my-app"        # update me

ecr_repositories = [
  "myapp/backend",
  "myapp/frontend",
]

# gitlab_flux_token — set via TF_VAR_gitlab_flux_token env var in CI, never commit this

# Restrict the EKS API endpoint to your CI runner IP range and/or VPN CIDR.
# "0.0.0.0/0" is the insecure default — replace before deploying to real accounts.
cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"] # replace with CI runner / VPN CIDRs

letsencrypt_email = "platform@example.com" # update me — used for Let's Encrypt cert expiry notifications
