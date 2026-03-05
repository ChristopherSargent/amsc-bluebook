variable "role_name" {
  type        = string
  description = "IAM role name"
}

variable "oidc_provider_arn" {
  type        = string
  description = "EKS OIDC provider ARN"
}

variable "oidc_provider" {
  type        = string
  description = "EKS OIDC provider URL without https://"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace of the service account"
}

variable "service_account" {
  type        = string
  description = "Kubernetes service account name"
}

variable "policy_arns" {
  type        = list(string)
  description = "Managed IAM policy ARNs to attach"
  default     = []
}

variable "inline_policy" {
  type        = string
  description = "Inline IAM policy JSON. Use jsonencode() at the call site."
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
