variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "cluster_name" {
  type    = string
  default = "eks-prod"
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

variable "globus_client_id" {
  type        = string
  description = "Globus Auth application client ID. Set via TF_VAR_globus_client_id — never commit."
  sensitive   = true
}

variable "globus_client_secret" {
  type        = string
  description = "Globus Auth application client secret. Set via TF_VAR_globus_client_secret — never commit."
  sensitive   = true
}

variable "mlflow_db_password" {
  type        = string
  description = "PostgreSQL password for the MLflow backend store. Set via TF_VAR_mlflow_db_password — never commit."
  sensitive   = true
}

variable "openmetadata_jwt_secret" {
  type        = string
  description = "Random secret used by OpenMetadata for internal JWT signing. Set via TF_VAR_openmetadata_jwt_secret — never commit."
  sensitive   = true
}

variable "mlflow_db_host" {
  type        = string
  description = "PostgreSQL hostname for the MLflow backend store (RDS endpoint recommended for prod)."
  default     = "postgresql.mlflow.svc.cluster.local"
}

variable "mlflow_host" {
  type        = string
  description = "Public DNS hostname for the MLflow ingress (e.g. mlflow.your-domain.com)."
}

variable "openmetadata_host" {
  type        = string
  description = "Public DNS hostname for the OpenMetadata ingress (e.g. openmetadata.your-domain.com)."
}

variable "kong_image_repository" {
  type        = string
  description = "ECR repository URL for the custom Kong image."
}

variable "kong_image_tag" {
  type        = string
  description = "Tag of the custom Kong image to deploy."
  default     = "3.9.0"
}
