output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "ci_deploy_role_arn" {
  description = "Set this as CI_DEPLOY_ROLE_ARN in GitLab CI/CD variables"
  value       = aws_iam_role.ci_deploy.arn
}

output "eso_irsa_role_arn" {
  value = module.eso_irsa.role_arn
}
