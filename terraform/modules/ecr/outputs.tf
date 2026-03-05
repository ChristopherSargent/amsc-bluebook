output "repository_urls" {
  description = "Map of repository name to URL"
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "registry_id" {
  description = "AWS account ID that owns the registry"
  value       = length(aws_ecr_repository.this) > 0 ? one(values(aws_ecr_repository.this)).registry_id : null
}

output "repository_arns" {
  description = "Map of repository name to ARN"
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}
