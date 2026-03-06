variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "cluster_name" {
  type    = string
  default = "eks-dev"
}

variable "cluster_version" {
  type        = string
  description = "Kubernetes version for the EKS cluster"
  default     = "1.32"
}

variable "gitlab_url" {
  type        = string
  description = "GitLab instance base URL (e.g. https://gitlab.com or https://gitlab.example.com)"
}

variable "config_repo_path" {
  type        = string
  description = "GitLab group/project path for this repo — Flux bootstraps here (e.g. my-org/amsc-bluebook)"
}

variable "gitlab_flux_token" {
  type        = string
  description = "GitLab deploy token with read_repository scope — used by Flux to pull config repo"
  sensitive   = true
}

variable "gitlab_project_path" {
  type        = string
  description = "GitLab group/project path for the app repo — used in CI OIDC trust condition"
}

variable "ecr_repositories" {
  type        = list(string)
  description = "ECR repository names to create"
  default     = []
}

variable "cluster_endpoint_public_access_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to reach the EKS API. Set to your CI runner IPs and VPN range."
  default     = ["0.0.0.0/0"]
}

variable "grafana_admin_password" {
  type        = string
  description = "Initial Grafana admin password. Set via TF_VAR_grafana_admin_password — never commit."
  sensitive   = true
}

variable "letsencrypt_email" {
  type        = string
  description = "Email address for Let's Encrypt certificate notifications and expiry warnings."
}
