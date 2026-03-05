aws_region   = "us-east-1"
environment  = "staging"
cluster_name = "eks-staging"

gitlab_url          = "https://gitlab.com"
config_repo_path    = "my-org/k8s-config"   # update me
gitlab_project_path = "my-org/my-app"        # update me

ecr_repositories = [
  "myapp/backend",
  "myapp/frontend",
]
