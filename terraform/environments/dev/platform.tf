# Platform IRSA roles and supporting AWS resources for all 8 cluster add-ons.
# Values are written into a ConfigMap in the cluster so Flux HelmReleases can
# consume them via substituteFrom without any manual ARN copying.

# ── 1. AWS Load Balancer Controller ──────────────────────────────────────────

resource "aws_iam_policy" "alb_controller" {
  name        = "alb-controller-${var.environment}"
  description = "IAM policy for the AWS Load Balancer Controller"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = "*"
        Condition = {
          StringEquals = { "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com" }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes", "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones", "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs", "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances", "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags", "ec2:GetCoipPoolUsage",
          "ec2:DescribeCoipPools", "ec2:GetSecurityGroupsForVpc",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:DescribeTrustStores",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:DescribeUserPoolClient",
          "acm:ListCertificates", "acm:DescribeCertificate",
          "iam:ListServerCertificates", "iam:GetServerCertificate",
          "waf-regional:GetWebACL", "waf-regional:GetWebACLForResource",
          "waf-regional:AssociateWebACL", "waf-regional:DisassociateWebACL",
          "wafv2:GetWebACL", "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL", "wafv2:DisassociateWebACL",
          "shield:GetSubscriptionState", "shield:DescribeProtection",
          "shield:CreateProtection", "shield:DeleteProtection",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress",
          "ec2:CreateSecurityGroup",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:DeleteSecurityGroup",
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:CreateRule", "elasticloadbalancing:DeleteRule",
          "elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:SetWebAcl",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:AddListenerCertificates",
          "elasticloadbalancing:RemoveListenerCertificates",
          "elasticloadbalancing:ModifyRule",
        ]
        Resource = "*"
      },
    ]
  })
}

module "alb_controller_irsa" {
  source            = "../../modules/irsa"
  role_name         = "alb-controller-${var.environment}"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider     = module.eks.oidc_provider
  namespace         = "kube-system"
  service_account   = "aws-load-balancer-controller"
  policy_arns       = [aws_iam_policy.alb_controller.arn]
  tags              = local.tags
}

# ── 2. Karpenter ─────────────────────────────────────────────────────────────
# Uses the official EKS module submodule which also creates:
#   - node IAM role
#   - SQS queue + EventBridge rules for spot interruption handling

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.0"

  cluster_name           = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn

  tags = local.tags
}

# ── 3. Metrics Server ─────────────────────────────────────────────────────────
# No AWS IAM needed — pure Kubernetes component.

# ── 4. cert-manager ───────────────────────────────────────────────────────────
# Needs Route53 access for DNS01 ACME challenge.

module "cert_manager_irsa" {
  source            = "../../modules/irsa"
  role_name         = "cert-manager-${var.environment}"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider     = module.eks.oidc_provider
  namespace         = "cert-manager"
  service_account   = "cert-manager"

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["route53:GetChange"]
        Resource = "arn:aws:route53:::change/*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets",
        ]
        Resource = "arn:aws:route53:::hostedzone/*"
      },
      {
        Effect   = "Allow"
        Action   = ["route53:ListHostedZonesByName"]
        Resource = "*"
      },
    ]
  })

  tags = local.tags
}

# ── 5. External DNS ───────────────────────────────────────────────────────────

module "external_dns_irsa" {
  source            = "../../modules/irsa"
  role_name         = "external-dns-${var.environment}"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider     = module.eks.oidc_provider
  namespace         = "external-dns"
  service_account   = "external-dns"

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = "arn:aws:route53:::hostedzone/*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource",
        ]
        Resource = "*"
      },
    ]
  })

  tags = local.tags
}

# ── 6. kube-prometheus-stack ──────────────────────────────────────────────────
# No AWS IAM needed — metrics stored in-cluster.

# ── 7. Loki ───────────────────────────────────────────────────────────────────
# See section 9 below — Loki S3 bucket and IRSA role are provisioned there.

# ── 8. Velero ─────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "velero" {
  bucket = "velero-${var.environment}-${data.aws_caller_identity.current.account_id}"
  tags   = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "velero" {
  bucket = aws_s3_bucket.velero.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "velero" {
  bucket                  = aws_s3_bucket.velero.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

module "velero_irsa" {
  source            = "../../modules/irsa"
  role_name         = "velero-${var.environment}"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider     = module.eks.oidc_provider
  namespace         = "velero"
  service_account   = "velero"

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVolumes", "ec2:DescribeSnapshots",
          "ec2:CreateTags", "ec2:CreateVolume",
          "ec2:CreateSnapshot", "ec2:DeleteSnapshot",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:DeleteObject", "s3:PutObject",
          "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts",
        ]
        Resource = "${aws_s3_bucket.velero.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.velero.arn
      },
    ]
  })

  tags = local.tags
}

# ── 9. Loki (S3 backend) ──────────────────────────────────────────────────────
# Durable log storage that survives pod restarts.
# The base HelmRelease uses filesystem (dev/staging); the prod kustomize patch
# switches to this S3 bucket via SimpleScalable mode.

resource "aws_s3_bucket" "loki" {
  bucket = "loki-${var.environment}-${data.aws_caller_identity.current.account_id}"
  tags   = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "loki" {
  bucket = aws_s3_bucket.loki.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "loki" {
  bucket                  = aws_s3_bucket.loki.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

module "loki_irsa" {
  source            = "../../modules/irsa"
  role_name         = "loki-${var.environment}"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider     = module.eks.oidc_provider
  namespace         = "monitoring"
  service_account   = "loki"

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:DeleteObject", "s3:PutObject",
          "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts",
        ]
        Resource = "${aws_s3_bucket.loki.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.loki.arn
      },
    ]
  })

  tags = local.tags
}

# ── 10. MLflow (S3 artifact store) ───────────────────────────────────────────

resource "aws_s3_bucket" "mlflow" {
  bucket = "mlflow-${var.environment}-${data.aws_caller_identity.current.account_id}"
  tags   = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "mlflow" {
  bucket = aws_s3_bucket.mlflow.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "mlflow" {
  bucket = aws_s3_bucket.mlflow.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "mlflow" {
  bucket                  = aws_s3_bucket.mlflow.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "mlflow" {
  bucket = aws_s3_bucket.mlflow.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

module "mlflow_irsa" {
  source            = "../../modules/irsa"
  role_name         = "mlflow-${var.environment}"
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider     = module.eks.oidc_provider
  namespace         = "mlflow"
  service_account   = "mlflow"

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:DeleteObject", "s3:PutObject",
          "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts",
        ]
        Resource = "${aws_s3_bucket.mlflow.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.mlflow.arn
      },
    ]
  })

  tags = local.tags
}

# ── cluster-vars ConfigMap ────────────────────────────────────────────────────
# Terraform writes all environment-specific values here after creating IAM roles.
# Flux HelmReleases consume them via `substituteFrom` so no ARNs need to be
# manually copied into the config repo.

resource "kubernetes_config_map" "cluster_vars" {
  metadata {
    name      = "cluster-vars"
    namespace = "flux-system"
  }

  data = {
    CLUSTER_NAME              = module.eks.cluster_name
    AWS_ACCOUNT_ID            = data.aws_caller_identity.current.account_id
    AWS_REGION                = var.aws_region
    VPC_ID                    = module.vpc.vpc_id
    ALB_CONTROLLER_ROLE_ARN   = module.alb_controller_irsa.role_arn
    KARPENTER_ROLE_ARN        = module.karpenter.iam_role_arn
    KARPENTER_NODE_ROLE_NAME  = module.karpenter.node_iam_role_name
    KARPENTER_QUEUE_NAME      = module.karpenter.queue_name
    CERT_MANAGER_ROLE_ARN     = module.cert_manager_irsa.role_arn
    EXTERNAL_DNS_ROLE_ARN     = module.external_dns_irsa.role_arn
    VELERO_ROLE_ARN           = module.velero_irsa.role_arn
    VELERO_BUCKET             = aws_s3_bucket.velero.bucket
    LOKI_ROLE_ARN             = module.loki_irsa.role_arn
    LOKI_BUCKET               = aws_s3_bucket.loki.bucket
    LETSENCRYPT_EMAIL         = var.letsencrypt_email
    # Kong custom image (built from docker/kong/Dockerfile, pushed to ECR)
    KONG_IMAGE_REPOSITORY     = var.kong_image_repository
    KONG_IMAGE_TAG            = var.kong_image_tag
    # MLflow
    MLFLOW_ROLE_ARN           = module.mlflow_irsa.role_arn
    MLFLOW_ARTIFACT_BUCKET    = aws_s3_bucket.mlflow.bucket
    MLFLOW_DB_HOST            = var.mlflow_db_host
    MLFLOW_HOST               = var.mlflow_host
    # OpenMetadata
    OPENMETADATA_HOST         = var.openmetadata_host
  }

  depends_on = [flux_bootstrap_git.this]
}

# ── cluster-secrets Secret ────────────────────────────────────────────────────
# Sensitive values are kept in a Secret (encrypted at rest via KMS) so they
# are never visible in the plaintext cluster-vars ConfigMap.
# Flux substituteFrom reads both — HelmReleases use ${GRAFANA_ADMIN_PASSWORD}
# as normal but the value comes from this Secret, not the ConfigMap.

resource "kubernetes_secret" "cluster_secrets" {
  metadata {
    name      = "cluster-secrets"
    namespace = "flux-system"
  }

  data = {
    GRAFANA_ADMIN_PASSWORD      = var.grafana_admin_password
    GLOBUS_CLIENT_ID            = var.globus_client_id
    GLOBUS_CLIENT_SECRET        = var.globus_client_secret
    MLFLOW_DB_PASSWORD          = var.mlflow_db_password
    OPENMETADATA_JWT_SECRET     = var.openmetadata_jwt_secret
  }

  depends_on = [flux_bootstrap_git.this]
}
