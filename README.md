# AWS Multi-Account EKS Platform

A Terraform-based platform for deploying portable, redeployable Kubernetes workloads across multiple AWS accounts (dev, staging, prod) using EKS, ECR, FluxCD, and GitLab CI — with no static AWS credentials anywhere.

---

## Architecture

```
GitLab CI (OIDC)
  |
  |-- terraform apply --> EKS + ECR + IAM (per account)
  |-- docker push     --> ECR (per account)
  |-- git push        --> config repo (values bump)
                              |
                        FluxCD (in-cluster, per env)
                              |-- pulls config repo
                              |-- applies HelmReleases
                              |-- reconciles drift

Per AWS Account:
  EKS Cluster
  ├── flux-system         FluxCD controllers
  ├── external-secrets    ECR token refresh via IRSA
  └── <your-app-ns>       Application workloads

  ECR Registry
  └── per-app repositories (created by Terraform)
```

**Key properties:**
- Each environment (dev/staging/prod) lives in a completely separate AWS account
- GitLab CI authenticates to AWS via OIDC — no access keys, no secrets rotation
- FluxCD runs inside each cluster and pulls from Git — no inbound cluster access required
- External Secrets Operator refreshes ECR auth tokens automatically via IRSA

---

## Repository Structure

```
.
├── .gitlab-ci.yml                  CI/CD pipeline
├── terraform/
│   ├── bootstrap/
│   │   └── main.tf                 Creates S3 state bucket + DynamoDB lock table
│   ├── modules/
│   │   ├── eks/                    EKS cluster + OIDC provider
│   │   ├── ecr/                    ECR repositories with lifecycle policies
│   │   └── irsa/                   IAM role for Kubernetes service accounts
│   └── environments/
│       ├── dev/                    Dev account config
│       ├── staging/                Staging account config
│       └── prod/                   Prod account config
└── adr/
    └── template.md                 Architecture decision record template
```

Each environment directory contains:

| File | Purpose |
|---|---|
| `backend.tf` | S3 remote state config (fill in after bootstrap) |
| `providers.tf` | AWS, Kubernetes, Helm, Flux provider config |
| `variables.tf` | Input variable declarations |
| `terraform.tfvars` | Environment-specific values |
| `main.tf` | Module calls: VPC, EKS, ECR, IAM, ESO, Flux |
| `outputs.tf` | Role ARNs and registry URLs to copy into GitLab CI variables |

---

## Prerequisites

**Tools** (install once locally and on your CI runner):

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.6
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) v2
- `kubectl` (for manual cluster inspection)

**AWS** (per target account):

- An AWS account with permissions to create IAM, EKS, ECR, VPC, and S3 resources
- No pre-existing infrastructure required — Terraform creates everything

**GitLab**:

- A GitLab group/project for this infrastructure repo
- A separate GitLab project for your app code
- A GitLab project for your Flux config repo (Helm values per environment)
- GitLab Runner with Docker-in-Docker support (for image builds)

---

## Setup

### Step 1 — Bootstrap remote state (run once per AWS account)

Terraform needs an S3 bucket and DynamoDB table to store state before it can manage anything else. Bootstrap these with local state first, then migrate.

Authenticate to the target account, then:

```bash
cd terraform/bootstrap

terraform init
terraform apply -var="environment=dev"
# note the output: state_bucket and lock_table names
```

Repeat for staging and prod accounts (change `-var="environment=..."` accordingly).

### Step 2 — Configure each environment

In each `terraform/environments/<env>/` directory:

**1. Update `backend.tf`** with the bucket name and account ID from Step 1:

```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-state-dev-123456789012"  # from bootstrap output
    key            = "eks/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks-dev"
    encrypt        = true
  }
}
```

**2. Update `terraform.tfvars`** with your GitLab paths:

```hcl
gitlab_url          = "https://gitlab.com"
config_repo_path    = "my-org/k8s-config"   # the Flux config repo
gitlab_project_path = "my-org/my-app"        # the app source repo
ecr_repositories    = ["myapp/backend", "myapp/frontend"]
```

**3. Set the Flux deploy token** as an environment variable (never commit this):

```bash
export TF_VAR_gitlab_flux_token="<gitlab-deploy-token-with-read_repository-scope>"
```

Create the deploy token in GitLab under your config repo: **Settings > Repository > Deploy tokens**.

### Step 3 — Apply Terraform

Authenticate to the target AWS account, then:

```bash
cd terraform/environments/dev

terraform init
terraform plan
terraform apply
```

This creates:
- VPC with public/private subnets across 3 AZs
- EKS cluster (K8s 1.30) with a managed node group
- ECR repositories for each app
- GitLab OIDC provider in IAM
- `ci-deploy` IAM role trusted by your GitLab CI pipeline
- IRSA role for External Secrets Operator
- External Secrets Operator (via Helm)
- Flux bootstrap (installs Flux into the cluster and commits its manifests to your config repo)

Repeat for staging and prod.

### Step 4 — Copy outputs into GitLab CI variables

After `terraform apply`, run:

```bash
terraform output
```

Go to your GitLab app project: **Settings > CI/CD > Variables**, and add:

| Variable | Value | Scope |
|---|---|---|
| `DEV_TF_ROLE_ARN` | `ci_deploy_role_arn` output from dev | All |
| `STAGING_TF_ROLE_ARN` | `ci_deploy_role_arn` output from staging | All |
| `PROD_TF_ROLE_ARN` | `ci_deploy_role_arn` output from prod | All |
| `DEV_ECR_REGISTRY` | account ID + `.dkr.ecr.us-east-1.amazonaws.com` | All |
| `CONFIG_REPO_PATH` | `my-org/k8s-config` | All |
| `CONFIG_REPO_TOKEN` | GitLab access token with `write_repository` | All (masked) |

### Step 5 — Create the Flux config repo

Flux bootstraps itself into a `clusters/<env>` path in your config repo. You need to create the app delivery manifests there. Minimum structure:

```
k8s-config/
└── clusters/
    ├── dev/
    │   ├── flux-system/          # created automatically by Flux bootstrap
    │   └── apps/
    │       ├── namespace.yaml    # your app namespace
    │       └── myapp.yaml        # HelmRelease pointing at ECR
    ├── staging/
    │   └── apps/
    └── prod/
        └── apps/
```

Example `HelmRelease` (`clusters/dev/apps/myapp.yaml`):

```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: myapp
  namespace: flux-system
spec:
  type: oci
  interval: 5m
  url: oci://<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/charts
---
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: myapp
  namespace: myapp
spec:
  interval: 5m
  chart:
    spec:
      chart: myapp
      version: "1.x"
      sourceRef:
        kind: HelmRepository
        name: myapp
  values:
    image:
      repository: <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/myapp/backend
      tag: "abc1234"   # GitLab CI bumps this on every deploy
```

---

## Day-to-Day Deploy Flow

Once set up, the loop is fully automated:

```
Developer merges PR to main
        |
        v
GitLab CI pipeline runs:
  1. Builds Docker image
  2. Pushes to dev ECR  (assumes ci-deploy role via OIDC)
  3. Bumps image tag in k8s-config repo (clusters/dev/apps/myapp.yaml)
        |
        v
FluxCD in dev cluster detects config repo change
  4. Pulls updated HelmRelease
  5. Upgrades the Helm release in-cluster
  6. Pod pulls new image from ECR (node role has ECR read access)
        |
        v
Developer manually triggers deploy:staging in GitLab
  (same flow, different account + ECR + config path)
        |
        v
Release tag created → deploy:prod pipeline available
  (manual approval gate required)
```

---

## Environment Differences

| | dev | staging | prod |
|---|---|---|---|
| Node type | t3.medium | t3.large | t3.xlarge |
| Node count | 1-3 | 2-6 | 3-10 |
| NAT gateway | Single (cost saving) | HA (one per AZ) | HA (one per AZ) |
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 |
| CI deploy trigger | Any branch | `main` branch only | Git tags only |
| CI apply gate | Automatic | Manual | Manual |
| IAM OIDC trust | Any branch | `ref:main` | `ref_type:tag` |

The IAM trust condition is enforced at the AWS level — not just in CI rules — so the restriction cannot be bypassed by editing `.gitlab-ci.yml`.

---

## Terraform Module Reference

### `modules/eks`

Creates an EKS cluster using `terraform-aws-modules/eks` v20.

| Variable | Default | Description |
|---|---|---|
| `cluster_name` | required | EKS cluster name |
| `cluster_version` | `"1.30"` | Kubernetes version |
| `vpc_id` | required | VPC to deploy into |
| `subnet_ids` | required | Private subnets for node group |
| `node_instance_type` | `t3.medium` | EC2 instance type |
| `node_min_size` | `1` | Min node count |
| `node_max_size` | `3` | Max node count |
| `node_desired_size` | `2` | Desired node count |

Key outputs: `cluster_name`, `cluster_endpoint`, `oidc_provider_arn`, `oidc_provider`

### `modules/ecr`

Creates ECR repositories with immutable tags, KMS encryption, scan-on-push, and a lifecycle policy.

| Variable | Default | Description |
|---|---|---|
| `repositories` | required | List of repo names to create |
| `image_retention_count` | `20` | Images to keep per repo |

Key outputs: `repository_urls`, `repository_arns`, `registry_id`

### `modules/irsa`

Creates an IAM role trusted by a specific Kubernetes service account via OIDC.

| Variable | Default | Description |
|---|---|---|
| `role_name` | required | IAM role name |
| `oidc_provider_arn` | required | From `modules/eks` output |
| `oidc_provider` | required | From `modules/eks` output |
| `namespace` | required | Kubernetes namespace |
| `service_account` | required | Kubernetes service account name |
| `policy_arns` | `[]` | Managed policy ARNs to attach |
| `inline_policy` | `null` | Inline policy JSON (`jsonencode(...)`) |

Key outputs: `role_arn`, `role_name`

---

## CI Pipeline Reference

The `.gitlab-ci.yml` pipeline has five stages:

| Stage | Jobs | When |
|---|---|---|
| `validate` | `tf:validate` (all envs) | Every MR and push to main |
| `plan` | `tf:plan:dev` (auto), `tf:plan:staging` (manual), `tf:plan:prod` (tags) | Push to main / tags |
| `apply` | `tf:apply:dev` (auto), `tf:apply:staging` (manual), `tf:apply:prod` (manual) | After plan |
| `build` | `build` — Docker image to ECR | Push to main / tags |
| `deploy` | `deploy:dev` (auto), `deploy:staging` (manual), `deploy:prod` (manual) | Push to main / tags |

**Required GitLab CI/CD variables:**

| Variable | Description | Sensitive |
|---|---|---|
| `DEV_TF_ROLE_ARN` | IAM role for dev Terraform | No |
| `STAGING_TF_ROLE_ARN` | IAM role for staging Terraform | No |
| `PROD_TF_ROLE_ARN` | IAM role for prod Terraform | No |
| `DEV_ECR_REGISTRY` | Dev ECR registry hostname | No |
| `STAGING_ECR_REGISTRY` | Staging ECR registry hostname | No |
| `PROD_ECR_REGISTRY` | Prod ECR registry hostname | No |
| `CONFIG_REPO_PATH` | GitLab path to Flux config repo | No |
| `CONFIG_REPO_TOKEN` | GitLab token with `write_repository` on config repo | Yes (mask) |
| `TF_VAR_gitlab_flux_token` | GitLab deploy token for Flux (read-only) | Yes (mask) |

---

## Adding a New Application

1. Add the repository names to `ecr_repositories` in each environment's `terraform.tfvars` and re-apply Terraform.
2. Add a `HelmRelease` manifest under `clusters/<env>/apps/` in the config repo.
3. Add a `build` job and a `deploy:<env>` job to `.gitlab-ci.yml` for the new app.

---

## Scaling to Additional AWS Accounts

To add a new environment (e.g., `sandbox`):

1. Copy `terraform/environments/dev/` to `terraform/environments/sandbox/`
2. Update `terraform.tfvars` and `backend.tf` for the new account
3. Run `terraform/bootstrap/main.tf` in the new account
4. Run `terraform apply` in the new environment directory
5. Add the role ARN and ECR registry outputs as GitLab CI variables
6. Add `tf:plan:sandbox`, `tf:apply:sandbox`, and `deploy:sandbox` jobs to `.gitlab-ci.yml`
7. Create `clusters/sandbox/` in the config repo
