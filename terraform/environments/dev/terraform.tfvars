aws_region   = "us-east-1"
environment  = "dev"
cluster_name = "eks-dev"

gitlab_url          = "https://gitlab.com"
config_repo_path    = "my-org/k8s-config"   # update me
gitlab_project_path = "my-org/my-app"        # update me

ecr_repositories = [
  "myapp/backend",
  "myapp/frontend",
]

# gitlab_flux_token — set via TF_VAR_gitlab_flux_token env var in CI, never commit this
