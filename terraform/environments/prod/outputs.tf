output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "ci_deploy_role_arn" {
  description = "IAM role ARN for GitLab CI — set as PROD_TF_ROLE_ARN in GitLab CI/CD variables"
  value       = aws_iam_role.ci_deploy.arn
}

output "ecr_registry" {
  description = "ECR registry hostname — set as PROD_ECR_REGISTRY in GitLab CI/CD variables"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

output "ecr_repository_urls" {
  description = "Map of repository name to full URL"
  value       = module.ecr.repository_urls
}

output "eso_irsa_role_arn" {
  description = "IRSA role ARN for External Secrets Operator"
  value       = module.eso_irsa.role_arn
}

output "kms_key_arn" {
  description = "KMS key ARN used for EKS secrets envelope encryption"
  value       = module.eks.kms_key_arn
}
