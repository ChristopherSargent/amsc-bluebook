# Bug fix: KMS key for envelope encryption of Kubernetes secrets at rest
resource "aws_kms_key" "eks_secrets" {
  description             = "EKS secrets encryption - ${var.cluster_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "eks_secrets" {
  name          = "alias/eks-${var.cluster_name}-secrets"
  target_key_id = aws_kms_key.eks_secrets.key_id
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Private access lets nodes and in-VPC callers reach the API without going
  # through the public endpoint. Public access is also enabled so CI runners
  # outside the VPC can reach the cluster — restrict the CIDRs to your runner
  # IPs and VPN range via cluster_endpoint_public_access_cidrs.
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  # Bug fix: encrypt secrets at rest with customer-managed KMS key
  cluster_encryption_config = {
    resources        = ["secrets"]
    provider_key_arn = aws_kms_key.eks_secrets.arn
  }

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size

      iam_role_additional_policies = {
        AmazonECRReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      }
    }
  }

  tags = var.tags
}
