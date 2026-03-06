---                                                                                                                                                                             
  Review: amsc-bluebook                                                                                                                                                                                                                                                                                                                                             
  Overall: This is a well-structured, thoughtfully designed reference implementation. The fundamentals are solid. No static credentials anywhere, OIDC-based auth throughout,     
  least-privilege IAM scoping, encryption at rest everywhere, immutable ECR tags, and a clean GitOps separation of concerns. Below are the specific issues found, ordered by
  severity.

  ---
  HIGH — Functional Bugs

  1. sed image-tag bumping is fragile (.gitlab-ci.yml:199)

  sed -i "s|tag:.*|tag: ${CI_COMMIT_SHORT_SHA}|" clusters/${DEPLOY_ENV}/apps/myapp-values.yaml

  Two problems:
  - tag:.* matches any YAML key named tag: — not just image.tag. If the values file has labels, chart version, or any other tag: field, they'll be clobbered.
  - The sed replacement strips leading whitespace from the matched line, corrupting YAML indentation.

  Fix: use yq instead — yq -i '.image.tag = "${CI_COMMIT_SHORT_SHA}"' — or at minimum anchor the pattern with indentation, e.g., s|^\(\s*tag:\).*|\1 ${CI_COMMIT_SHORT_SHA}|.     

  2. Build only pushes to dev ECR; staging/prod can't pull the image (.gitlab-ci.yml:182-187)

  build:
    variables:
      AWS_ROLE_ARN: $DEV_TF_ROLE_ARN    # dev role only
    script:
      - docker push $DEV_ECR_REGISTRY/myapp/backend:$CI_COMMIT_SHORT_SHA

  Each environment is a separate AWS account with its own ECR. The deploy jobs for staging and prod will bump the tag in the config repo, but the image only exists in the dev    
  account's ECR. Nodes in staging/prod accounts cannot pull it without explicit cross-account ECR resource policies. The comment acknowledges this but it's a real functional     
  break.

  Fix: add separate build steps per account (or configure cross-account pull permissions on the staging/prod ECR repos pointing at dev).

  ---
  MEDIUM — Security

  3. cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"] committed in prod.tfvars (terraform/environments/prod/terraform.tfvars:14)

  The EKS API is publicly accessible from the entire internet in all three committed tfvars files. The comments say to replace it, but the placeholder value is a working,        
  insecure CIDR. For a reference implementation, the prod value should be something that fails obviously (e.g., ["REPLACE_WITH_CI_RUNNER_AND_VPN_CIDRS"]) so it can never
  accidentally be applied as-is.

  4. No prevent_destroy lifecycle on critical resources

  KMS keys (EKS + ECR), the EKS cluster itself, ECR repositories, and the Velero S3 bucket have no lifecycle { prevent_destroy = true }. A terraform destroy in the wrong
  environment would wipe production data irreversibly within the KMS key deletion window.

  5. KMS key deletion window is 7 days in all environments (modules/eks/main.tf:4, modules/ecr/main.tf:3)

  AWS recommends 30 days for production KMS keys. 7 days leaves very little time to detect and recover from an accidental terraform destroy before the key is permanently gone.   

  ---
  MEDIUM — Reliability

  6. Loki uses ephemeral filesystem storage in all environments (infrastructure/base/loki/helmrelease.yaml:22-26)

  loki:
    storage:
      type: filesystem
  singleBinary:
    replicas: 1

  A pod restart or rescheduling wipes all logs. There's no prod overlay switching this to S3 backend or a persistent volume. Prod needs either storage.type: s3 (with an IRSA     
  role, similar to Velero) or a PVC with a storageClass that survives pod termination.

  7. Velero S3 bucket has no lifecycle expiry rule (terraform/environments/*/platform.tf)

  The bucket has versioning enabled (which accumulates noncurrent object versions indefinitely), but no aws_s3_bucket_lifecycle_configuration. Velero manages backup TTL (30d)    
  within its own logic, but old object versions silently accumulate in S3. Add a lifecycle rule to expire noncurrent versions after 90 days, matching the state bucket.

  ---
  LOW — Correctness / Maintainability

  8. No .terraform.lock.hcl files committed

  terraform/.gitignore:5 explicitly says "do NOT ignore .terraform.lock.hcl" — but no lock files exist in the repo. Without them, terraform init on a fresh runner resolves       
  provider versions from scratch and can pull different patch versions. Run terraform providers lock in each environment directory and commit the resulting files.

  9. Kubernetes version 1.30 hardcoded in all main.tf files rather than in tfvars/variables.tf

  Every environment's main.tf has cluster_version = "1.30" as a literal. Upgrading K8s requires touching three Terraform source files instead of one variable. Expose it through  
  variables.tf with a default, and override in tfvars per environment.

  10. Significant main.tf and platform.tf duplication across environments

  The three environment main.tf files differ only in CIDR blocks, node sizes, and the IAM OIDC sub trust condition. The three platform.tf files are identical. A shared parent    
  module parameterizing those differences would eliminate drift risk and reduce future maintenance burden. This is a known trade-off for a reference implementation, but worth    
  noting.

  ---
  What's Correct and Production-Worthy

  Everything else is in good shape:

  - OIDC-everywhere: no static AWS credentials, no secrets rotation required
  - IRSA trust policies use both sub and aud conditions (prevents confused-deputy attacks)
  - GitLab OIDC trust correctly scoped per environment: any branch → main only → tags only; enforced at AWS IAM level, not just CI rules
  - ECR: immutable tags, scan-on-push, KMS encryption, lifecycle policy
  - State bucket: KMS encrypted, versioned, public access blocked, noncurrent version expiry
  - EKS secrets envelope encryption with customer-managed KMS key + rotation enabled
  - Velero S3: encrypted, versioned, public access blocked
  - ALB controller IAM policy minimal with iam:AWSServiceName condition on CreateServiceLinkedRole
  - Route53 policies correctly scoped (not full admin)
  - Kong admin API kept ClusterIP (not externally exposed)
  - Hubble UI and Grafana ingress disabled by default
  - cluster-secrets keeps passwords out of the ConfigMap
  - terraform.tfvars excludes secrets; sensitive values require TF_VAR_* env vars
  - terraform/.gitignore correctly excludes state/plan/cache but NOT lock files
  - Resource requests/limits set on all Helm deployments
  - ALB controller HA (replicaCount: 2), Karpenter spot interruption via SQS

  ---
  Summary of required fixes before deploying to real AWS accounts:

  ┌─────┬──────────┬──────────────────────────────────────────────────────────────────────┬───────────────────────────────────────────────────────────────────┐
  │  #  │ Severity │                                 File                                 │                                Fix                                │
  ├─────┼──────────┼──────────────────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────┤
  │ 1   │ HIGH     │ .gitlab-ci.yml:199                                                   │ Replace sed with yq for YAML-safe tag bumping                     │
  ├─────┼──────────┼──────────────────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────┤
  │ 2   │ HIGH     │ .gitlab-ci.yml:182-187                                               │ Add ECR push jobs for staging and prod accounts                   │
  ├─────┼──────────┼──────────────────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────┤
  │ 3   │ MEDIUM   │ environments/*/terraform.tfvars                                      │ Replace 0.0.0.0/0 with a string that fails validation             │
  ├─────┼──────────┼──────────────────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────┤
  │ 4   │ MEDIUM   │ modules/eks/main.tf, modules/ecr/main.tf, environments/*/platform.tf │ Add lifecycle { prevent_destroy = true } on KMS, EKS, ECR, S3     │
  ├─────┼──────────┼──────────────────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────┤
  │ 5   │ MEDIUM   │ modules/eks/main.tf:4, modules/ecr/main.tf:3                         │ Set deletion_window_in_days = 30 for prod                         │
  ├─────┼──────────┼──────────────────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────┤
  │ 6   │ MEDIUM   │ infrastructure/base/loki/helmrelease.yaml                            │ Add prod overlay with S3 backend or persistent storage            │
  ├─────┼──────────┼──────────────────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────┤
  │ 7   │ MEDIUM   │ terraform/environments/*/platform.tf                                 │ Add S3 lifecycle rule for Velero bucket noncurrent versions       │
  ├─────┼──────────┼──────────────────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────┤
  │ 8   │ LOW      │ terraform/environments/*/                                            │ Run terraform providers lock and commit .terraform.lock.hcl files │
  ├─────┼──────────┼──────────────────────────────────────────────────────────────────────┼───────────────────────────────────────────────────────────────────┤
  │ 9   │ LOW      │ terraform/environments/*/main.tf                                     │ Move cluster_version to variables.tf / tfvars                     │
  └─────┴──────────┴──────────────────────────────────────────────────────────────────────┴───────────────────────────────────────────────────────────────────┘
l