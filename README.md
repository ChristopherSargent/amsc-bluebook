<p align="center">
  <a href="https://american-science-cloud.github.io/amsc-site/">
    <img src="docs/amsc_logo.svg" alt="American Science Cloud" width="340">
  </a>
</p>

<p align="center">
  <a href="https://american-science-cloud.github.io/amsc-site/">american-science-cloud.github.io/amsc-site</a>
</p>

# amsc-bluebook

The reference implementation for deploying portable, redeployable Kubernetes
infrastructure across multiple AWS accounts for the **American Science Cloud (AmSC)**
project. Built on EKS, ECR, FluxCD, and GitLab CI — with no static AWS credentials
anywhere.

Licensed under [Apache 2.0](LICENSE). Copyright 2025 American Science Cloud (AmSC).

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
  ├── kube-system         Cilium (eBPF networking + Hubble observability)
  ├── kube-system         AWS Load Balancer Controller (ALB/NLB provisioning)
  ├── kube-system         Karpenter (node autoscaling)
  ├── kube-system         Metrics Server (HPA support)
  ├── kong                Kong Gateway OSS + kong-openid-connect plugin (Globus Auth)
  ├── cert-manager        cert-manager (TLS via Let's Encrypt DNS-01)
  ├── external-dns        External DNS (Route53 automation)
  ├── monitoring          kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
  ├── monitoring          Loki + Promtail (log aggregation)
  ├── velero              Velero (cluster backup to S3)
  ├── flux-system         FluxCD controllers
  ├── external-secrets    ECR token refresh via IRSA
  ├── mlflow              MLflow (ML experiment tracking, model registry — S3 artifacts via IRSA)
  ├── openmetadata        OpenMetadata (data catalog, lineage, governance)
  └── <team-app-ns>       Additional team application workloads

  ECR Registry
  ├── per-app repositories (created by Terraform)
  └── kong-custom         Custom Kong image with OIDC plugin pre-installed
```

**Key properties:**
- Each environment (dev/staging/prod) lives in a completely separate AWS account
- GitLab CI authenticates to AWS via OIDC — no access keys, no secrets rotation
- FluxCD runs inside each cluster and pulls from Git — no inbound cluster access required
- External Secrets Operator is pre-deployed with an IRSA role scoped to ECR — add ExternalSecret resources to manage Kubernetes Secrets from AWS Secrets Manager or ECR
- Cilium enforces network policy at the kernel level via eBPF — no sidecar proxies required
- Kong provides API gateway capabilities (rate limiting, auth plugins, L7 routing) in front of services

---

## Platform Components

| Component | Namespace | Purpose | IAM Required |
|---|---|---|---|
| Cilium | `kube-system` | eBPF networking, network policy, Hubble observability | No |
| AWS Load Balancer Controller | `kube-system` | Provisions ALBs/NLBs from Ingress resources | Yes (IRSA) |
| Karpenter | `kube-system` | Node autoscaling with spot interruption handling | Yes (IRSA) |
| Metrics Server | `kube-system` | Provides CPU/memory metrics for HPA | No |
| Kong Gateway OSS + kong-openid-connect | `kong` | API gateway: L7 routing, rate limiting, Globus OIDC auth | No |
| cert-manager | `cert-manager` | Automatic TLS certificates via Let's Encrypt DNS-01 | Yes (IRSA) |
| External DNS | `external-dns` | Syncs Route53 records from Kubernetes Services/Ingresses | Yes (IRSA) |
| kube-prometheus-stack | `monitoring` | Prometheus, Grafana, Alertmanager | No |
| Loki + Promtail | `monitoring` | Log aggregation and shipping | Yes (IRSA) — S3 backend in prod |
| Velero | `velero` | Cluster backup and restore to S3 | Yes (IRSA) |
| External Secrets Operator | `external-secrets` | Kubernetes Secrets from AWS Secrets Manager / ECR (pre-deployed; add ExternalSecret resources to activate) | Yes (IRSA) |

---

## Repository Structure

```
.
├── .gitlab-ci.yml                  CI/CD pipeline
├── docker/
│   └── kong/
│       └── Dockerfile              Custom Kong image with kong-openid-connect plugin
├── terraform/
│   ├── bootstrap/
│   │   └── main.tf                 Creates S3 state bucket + DynamoDB lock table
│   ├── modules/
│   │   ├── eks/                    EKS cluster + KMS secrets encryption
│   │   ├── ecr/                    ECR repositories with lifecycle policies
│   │   └── irsa/                   IAM role for Kubernetes service accounts
│   └── environments/
│       ├── dev/                    Dev account: main.tf, platform.tf, providers.tf
│       ├── staging/                Staging account: same structure, larger nodes, HA NAT
│       └── prod/                   Prod account: same structure, tag-only deploys
├── clusters/
│   ├── dev/
│   │   ├── infrastructure.yaml     Flux Kustomization — points at infrastructure/dev
│   │   └── apps.yaml               Flux Kustomization — points at apps/dev, dependsOn infrastructure
│   ├── staging/
│   │   ├── infrastructure.yaml
│   │   └── apps.yaml
│   └── prod/
│       ├── infrastructure.yaml
│       └── apps.yaml
├── infrastructure/
│   ├── sources/                    HelmRepository sources (one file per upstream)
│   ├── base/                       HelmRelease base configs (platform components)
│   │   ├── cilium/
│   │   ├── aws-load-balancer-controller/
│   │   ├── kong/                   Includes globus-jwt-plugin.yaml (KongClusterPlugin CRDs)
│   │   ├── karpenter/
│   │   ├── metrics-server/
│   │   ├── cert-manager/
│   │   ├── external-dns/
│   │   ├── kube-prometheus-stack/
│   │   ├── loki/
│   │   └── velero/
│   ├── dev/
│   │   └── kustomization.yaml      Flux reconciliation target for dev (base, filesystem Loki)
│   ├── staging/
│   │   └── kustomization.yaml      Flux reconciliation target for staging (base, filesystem Loki)
│   └── prod/
│       ├── kustomization.yaml      Flux reconciliation target for prod (base + patches)
│       └── patches/
│           ├── loki-s3.yaml        Overrides Loki to S3-backed SimpleScalable mode
│           └── promtail.yaml       Redirects Promtail push URL to loki-gateway (SimpleScalable)
└── apps/
    ├── base/                       HelmRelease base configs (application workloads)
    │   ├── mlflow/                 MLflow tracking server (S3 artifacts, PostgreSQL backend)
    │   └── openmetadata/           OpenMetadata + dependencies (Elasticsearch, MySQL)
    ├── dev/
    │   └── kustomization.yaml      Includes base apps for dev (add env-specific patches here)
    ├── staging/
    │   └── kustomization.yaml
    └── prod/
        └── kustomization.yaml
```

Each environment directory contains:

| File | Purpose |
|---|---|
| `backend.tf` | S3 remote state config (fill in after bootstrap) |
| `providers.tf` | AWS, Kubernetes, Helm, Flux provider config |
| `variables.tf` | Input variable declarations |
| `terraform.tfvars` | Environment-specific values |
| `main.tf` | Module calls: VPC, EKS, ECR, IAM, ESO, Flux |
| `platform.tf` | IRSA roles + Velero S3 bucket + cluster-vars ConfigMap + cluster-secrets Secret |

---

## Prerequisites

**Tools** (install once locally and on your CI runner):

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.9
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) v2
- [flux CLI](https://fluxcd.io/flux/installation/#install-the-flux-cli) — required to monitor reconciliation and force resyncs
- `kubectl` — for manual cluster inspection
- `helm` — optional but needed for debugging HelmRelease failures (`helm list -A`, `helm status`)

**AWS** (per target account):

- An AWS account with permissions to create IAM, EKS, ECR, VPC, S3, KMS, and DynamoDB resources
- A **Route53 hosted zone** for your domain in each account — required by cert-manager (DNS-01 TLS challenge) and External DNS (automatic record creation). If you don't have one, create it in the AWS console before running Terraform.
- A **domain name** delegated to that hosted zone
- No other pre-existing infrastructure required — Terraform creates everything else

**GitLab**:

- A fork or clone of this repo pushed to your GitLab group — this repo serves as both the infrastructure definition **and** the Flux config repo. Flux bootstraps into it and watches the `clusters/<env>/` and `infrastructure/` directories that are already here.
- A separate GitLab project for your app code (source of Docker builds)
- A GitLab Runner with Docker-in-Docker support (for image builds)

**Before you deploy, update these placeholders:**

| Placeholder | File | What to set |
|---|---|---|
| `config_repo_path = "my-org/amsc-bluebook"` | `terraform/environments/*/terraform.tfvars` | GitLab path to **this** repo (e.g. `john-doe/amsc-bluebook`). Terraform passes it to the Flux provider so Flux knows where to bootstrap. |
| `gitlab_project_path = "my-org/my-app"` | `terraform/environments/*/terraform.tfvars` | GitLab path to your **app source** repo (e.g. `john-doe/my-api`). Used only to construct the IAM OIDC trust condition — controls which GitLab project is allowed to assume the AWS deploy role. |
| `myapp/backend` | `.gitlab-ci.yml` | ECR repository name for your app image. Must match an entry in `ecr_repositories` in `terraform.tfvars`. The `build:*` jobs push to `$ECR_REGISTRY/<this-name>:$CI_COMMIT_SHORT_SHA` — update it to match your actual repo name (e.g. `john-doe-api/server`). |

> **Note:** The `build:*` and `deploy:*` jobs in `.gitlab-ci.yml` are provided as a reference template. They are intended to live in your **app repo's** CI pipeline, not this one. Copy the `.build-base`, `.deploy`, and `.aws-auth` blocks into your app project's `.gitlab-ci.yml` and adjust the `docker build` context and image name there.

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
config_repo_path    = "my-org/amsc-bluebook"  # path to THIS repo in GitLab — Flux bootstraps here
gitlab_project_path = "my-org/my-app"          # the app source repo — used in CI OIDC trust condition
cluster_version     = "1.32"
ecr_repositories    = ["myapp/backend", "myapp/frontend"]

cluster_endpoint_public_access_cidrs = ["203.0.113.0/24"]  # see Step 2.3 below

letsencrypt_email = "platform@your-domain.com"
```

**3. Set `cluster_endpoint_public_access_cidrs`** to the IPs that need to reach the EKS API server — update this in `terraform.tfvars` for each environment.

> **Security:** leaving this as `["0.0.0.0/0"]` exposes the Kubernetes API to the entire internet. Always replace it before deploying to real accounts.

This must include:
- Your **CI runner IPs** — the host(s) that run `terraform apply` and `helm` commands. For GitLab.com shared runners, check [gitlab.com/gitlab-com/runner-ips](https://gitlab.com/gitlab-com/runner-ips). For self-hosted runners, use the runner host's static/Elastic IP.
- Your **VPN egress IP(s)** — the IP your team exits through on VPN, so developers can run `kubectl` locally.

```bash
# Find your current public IP from any machine that needs access:
curl -s https://checkip.amazonaws.com
```

```hcl
# Example — replace all values with your real IPs:
cluster_endpoint_public_access_cidrs = [
  "35.231.145.151/32",   # GitLab CI runner static IP
  "10.8.0.0/16",         # Corporate VPN egress range
  "203.0.113.42/32",     # Office static IP
]
```

Use `/32` for a single host, a wider prefix (e.g. `/24`) for a DHCP pool or VPN range.

**4. Set sensitive variables** as environment variables (never commit these):

```bash
export TF_VAR_gitlab_flux_token="<gitlab-deploy-token-with-read_repository-scope>"
export TF_VAR_grafana_admin_password="<initial-grafana-password>"
export TF_VAR_globus_client_id="<globus-auth-client-id>"
export TF_VAR_globus_client_secret="<globus-auth-client-secret>"
export TF_VAR_mlflow_db_password="<postgresql-password-for-mlflow>"
export TF_VAR_openmetadata_jwt_secret="<random-secret-for-openmetadata-jwt-signing>"
```

Create the GitLab deploy token under **this repo**: **Settings > Repository > Deploy tokens**. Grant `read_repository` scope only.

Register a Globus Auth application at [app.globus.org/settings/developers](https://app.globus.org/settings/developers) to obtain the client ID and secret. Set the redirect URI to `https://<OPENMETADATA_HOST>/callback`.

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
- EKS cluster (version set in `cluster_version` tfvar) with a managed node group and KMS secrets encryption
- ECR repositories for each app
- GitLab OIDC provider in IAM
- `ci-deploy` IAM role trusted by your GitLab CI pipeline
- IRSA roles for all platform components (ALB Controller, Karpenter, cert-manager, External DNS, Velero, Loki, ESO)
- Velero S3 bucket (KMS encrypted, versioned, no public access)
- External Secrets Operator (via Helm)
- Flux bootstrap (installs Flux into the cluster and commits its manifests to your config repo)
- `cluster-vars` ConfigMap and `cluster-secrets` Secret in `flux-system` (consumed by all HelmReleases)

Repeat for staging and prod.

> **First-boot reconciliation:** On the first Flux sync after `terraform apply`, two components will fail briefly before self-healing:
> - **Karpenter** — `EC2NodeClass` and `NodePool` resources are applied at the same time as the Karpenter HelmRelease. The CRDs they require are registered by the HelmRelease, so they fail with "no matches for kind" on the first pass and succeed on the next Flux retry (~10 minutes).
> - **cert-manager** — The `ClusterIssuer` is applied alongside the cert-manager HelmRelease and fails similarly until the HelmRelease finishes installing the CRDs.
>
> Both are self-healing. No action is needed — watch `flux get kustomizations -A` and wait for all statuses to become `Ready`.

### Step 3b — Pin provider versions (run once per environment, commit the result)

After the first `terraform init`, generate lock files so CI always resolves identical provider versions:

```bash
cd terraform/environments/dev
terraform providers lock \
  -platform=linux_amd64 \
  -platform=darwin_arm64

cd ../staging
terraform providers lock \
  -platform=linux_amd64 \
  -platform=darwin_arm64

cd ../prod
terraform providers lock \
  -platform=linux_amd64 \
  -platform=darwin_arm64
```

Add `-platform=` for every OS/arch combination your team uses locally and in CI. Then commit the results:

```bash
git add terraform/environments/dev/.terraform.lock.hcl
git add terraform/environments/staging/.terraform.lock.hcl
git add terraform/environments/prod/.terraform.lock.hcl
git commit -m "chore: pin terraform provider versions"
git push
```

Without these files, `terraform init` on a fresh CI runner resolves provider versions from scratch and may pull different patch releases, producing non-reproducible plans.

### Step 4 — Copy outputs into GitLab CI variables

After `terraform apply`, run:

```bash
terraform output
```

The Terraform jobs run in **this repo's** CI pipeline; the build/deploy jobs run in your **app project's** CI pipeline (see the CI pipeline split note in the CI Pipeline Reference section). Set variables accordingly:

**This repo** — **Settings > CI/CD > Variables** (used by the `tf:plan/apply` Terraform jobs):

| Variable | Value | Scope |
|---|---|---|
| `DEV_TF_ROLE_ARN` | `ci_deploy_role_arn` output from dev | All |
| `STAGING_TF_ROLE_ARN` | `ci_deploy_role_arn` output from staging | All |
| `PROD_TF_ROLE_ARN` | `ci_deploy_role_arn` output from prod | All |
| `TF_VAR_gitlab_flux_token` | GitLab deploy token for Flux (`read_repository` on this repo) | All (masked) |
| `TF_VAR_grafana_admin_password` | Initial Grafana admin password | All (masked) |

**App project** — **Settings > CI/CD > Variables** (used by the `build:*` and `deploy:*` jobs):

| Variable | Value | Scope |
|---|---|---|
| `DEV_TF_ROLE_ARN` | Same as above (role also grants ECR push in dev account) | All |
| `STAGING_TF_ROLE_ARN` | Same as above | All |
| `PROD_TF_ROLE_ARN` | Same as above | All |
| `DEV_ECR_REGISTRY` | `ecr_registry` output from dev (e.g. `123456789012.dkr.ecr.us-east-1.amazonaws.com`) | All |
| `STAGING_ECR_REGISTRY` | `ecr_registry` output from staging | All |
| `PROD_ECR_REGISTRY` | `ecr_registry` output from prod | All |
| `CONFIG_REPO_PATH` | GitLab path to this repo (e.g. `my-org/amsc-bluebook`) | All |
| `CONFIG_REPO_TOKEN` | GitLab access token with `write_repository` scope on this repo | All (masked) |

### Step 5 — Deploy the data platform applications (MLflow + OpenMetadata)

The `apps/` tree is already wired into Flux via `clusters/<env>/apps.yaml`, which has `dependsOn: infrastructure` so it only reconciles after Kong, cert-manager, and external-dns are healthy.

Before Flux can reconcile the apps, add the required variables to Terraform `platform.tf` for each environment and re-apply:

```hcl
# In cluster-vars ConfigMap (non-sensitive):
"KONG_IMAGE_REPOSITORY" = "<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/kong-custom"
"KONG_IMAGE_TAG"         = "3.9.0"
"MLFLOW_ARTIFACT_BUCKET" = aws_s3_bucket.mlflow.id
"MLFLOW_ROLE_ARN"        = module.irsa_mlflow.role_arn
"MLFLOW_DB_HOST"         = "<rds-or-in-cluster-postgres-host>"
"MLFLOW_HOST"            = "mlflow.dev.your-domain.com"
"OPENMETADATA_HOST"      = "openmetadata.dev.your-domain.com"

# In cluster-secrets Secret (sensitive):
"GLOBUS_CLIENT_ID"       = var.globus_client_id
"GLOBUS_CLIENT_SECRET"   = var.globus_client_secret
"MLFLOW_DB_PASSWORD"     = var.mlflow_db_password
"OPENMETADATA_JWT_SECRET" = var.openmetadata_jwt_secret
```

Build and push the custom Kong image once per account before deploying:

```bash
cd docker/kong
docker build -t <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/kong-custom:3.9.0 .
docker push <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/kong-custom:3.9.0
```

### Step 6 — Add your own application manifests

To deploy a team application, add it to the `apps/` tree:

```
apps/
└── base/
    └── your-app/
        ├── kustomization.yaml
        └── helmrelease.yaml      # annotate Ingress with konghq.com/plugins: globus-oidc-api
```

Then add `../base/your-app` to `apps/dev/kustomization.yaml` (and staging/prod when ready). A `clusters/<env>/apps.yaml` Flux Kustomization already exists — no new cluster-level files are needed.

> **Helm chart prerequisite:** The HelmRepository expects your Helm chart packaged as an OCI artifact at `oci://<ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/charts/myapp`. Add a `helm package` + `helm push` step to your app's CI pipeline to publish the chart to ECR. Alternatively, point the HelmRepository at a public chart registry (e.g. Bitnami, Artifact Hub) and override only the `image.tag` in `values:`.

---

## Day-to-Day Deploy Flow

Once set up, the loop is fully automated:

```
Developer merges PR to main
        |
        v
GitLab CI pipeline runs (build:dev + deploy:dev, automatic):
  1. build:dev assumes DEV_TF_ROLE_ARN via OIDC
  2. Builds Docker image, pushes to dev account ECR
  3. deploy:dev bumps .spec.values.image.tag in apps/base/<your-app>/helmrelease.yaml (app repo CI)
        |
        v
FluxCD in dev cluster detects change in this repo
  4. Pulls updated HelmRelease (via apps/dev/kustomization.yaml → apps/base/<your-app>/)
  5. Upgrades the Helm release in-cluster
  6. Pod pulls new image from dev ECR (node role has ECR read access)
        |
        v
Developer manually triggers build:staging + deploy:staging in GitLab
  (build:staging pushes to staging account ECR, deploy:staging bumps apps/base/<your-app>/helmrelease.yaml)
        |
        v
Release tag created → build:prod + deploy:prod available (both manual)
  (build:prod pushes to prod account ECR, deploy:prod bumps apps/base/<your-app>/helmrelease.yaml)
```

---

## Environment Differences

| | dev | staging | prod |
|---|---|---|---|
| Node type | t3.medium | t3.large | t3.xlarge |
| Node count | 1-3 | 2-6 | 3-10 |
| NAT gateway | Single (cost saving) | HA (one per AZ) | HA (one per AZ) |
| VPC CIDR | 10.0.0.0/16 | 10.1.0.0/16 | 10.2.0.0/16 |
| Loki storage | Filesystem (ephemeral) | Filesystem (ephemeral) | S3 (SimpleScalable, HA) |
| CI build trigger | Auto on `main` | Manual | Manual (tags only) |
| CI deploy trigger | Auto on `main` | Manual | Manual (tags only) |
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
| `cluster_version` | `"1.32"` | Kubernetes version — set in `terraform.tfvars` |
| `vpc_id` | required | VPC to deploy into |
| `subnet_ids` | required | Private subnets for node group |
| `node_instance_type` | `t3.medium` | EC2 instance type |
| `node_min_size` | `1` | Min node count |
| `node_max_size` | `3` | Max node count |
| `node_desired_size` | `2` | Desired node count |
| `cluster_endpoint_public_access_cidrs` | `["0.0.0.0/0"]` | CIDRs allowed to reach the API server — **replace before deploying** |

Key outputs: `cluster_name`, `cluster_endpoint`, `oidc_provider_arn`, `oidc_provider`, `kms_key_arn`

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
| `build` | `build:dev` (auto), `build:staging` (manual), `build:prod` (tags, manual) | Push to main / tags |
| `deploy` | `deploy:dev` (auto), `deploy:staging` (manual), `deploy:prod` (manual) | After respective build |

Each `build:<env>` job assumes the corresponding account's IAM role and pushes directly to that account's ECR registry — no cross-account ECR access required. `deploy:<env>` gates on `build:<env>` completing first.

> **CI pipeline split:** The Terraform jobs (`tf:validate`, `tf:plan:*`, `tf:apply:*`) belong in **this repo's** `.gitlab-ci.yml` and are already configured. The `build:*` and `deploy:*` jobs are intended for your **application repo's** CI pipeline — copy the `.build-base` and `.deploy` templates (and the `.aws-auth` helper) into the app project's `.gitlab-ci.yml`, adjusting `docker build` context and `yq` path (`apps/base/<your-app>/helmrelease.yaml`) as needed. Set all the variables listed below in the app repo's CI/CD settings.

> **Required customization:** The `build:*` jobs in `.gitlab-ci.yml` contain `myapp/backend` as a placeholder image name. Replace every occurrence with your actual ECR repository name (e.g. `yourapp/api`) before the pipeline will push to the correct repository.

**Required GitLab CI/CD variables** (see Step 4 for full setup instructions):

| Variable | Description | Project | Sensitive |
|---|---|---|---|
| `DEV_TF_ROLE_ARN` | IAM role for dev (Terraform + ECR push) | This repo + app repo | No |
| `STAGING_TF_ROLE_ARN` | IAM role for staging | This repo + app repo | No |
| `PROD_TF_ROLE_ARN` | IAM role for prod | This repo + app repo | No |
| `DEV_ECR_REGISTRY` | Dev ECR registry hostname | App repo | No |
| `STAGING_ECR_REGISTRY` | Staging ECR registry hostname | App repo | No |
| `PROD_ECR_REGISTRY` | Prod ECR registry hostname | App repo | No |
| `CONFIG_REPO_PATH` | GitLab path to this repo (e.g. `my-org/amsc-bluebook`) | App repo | No |
| `CONFIG_REPO_TOKEN` | Token with `write_repository` on this repo | App repo | Yes (mask) |
| `TF_VAR_gitlab_flux_token` | GitLab deploy token for Flux (read-only on this repo) | This repo | Yes (mask) |
| `TF_VAR_grafana_admin_password` | Initial Grafana admin password | This repo | Yes (mask) |
| `TF_VAR_globus_client_id` | Globus Auth application client ID | This repo | Yes (mask) |
| `TF_VAR_globus_client_secret` | Globus Auth application client secret | This repo | Yes (mask) |

**Additional `cluster-vars` ConfigMap entries** (added to Terraform `platform.tf` alongside existing ARNs):

| Key | Description |
|---|---|
| `KONG_IMAGE_REPOSITORY` | ECR URL for the custom Kong image (e.g. `123456789012.dkr.ecr.us-east-1.amazonaws.com/kong-custom`) |
| `KONG_IMAGE_TAG` | Tag of the built Kong image (e.g. `3.9.0`) |
| `MLFLOW_ARTIFACT_BUCKET` | S3 bucket name for MLflow experiment artifacts |
| `MLFLOW_ROLE_ARN` | IRSA role ARN for MLflow S3 access |
| `MLFLOW_DB_HOST` | PostgreSQL host for MLflow backend store |
| `MLFLOW_HOST` | DNS hostname for MLflow ingress (e.g. `mlflow.dev.your-domain.com`) |
| `OPENMETADATA_HOST` | DNS hostname for OpenMetadata ingress |

---

## Networking: Cilium + Kong

### Cilium

Cilium runs in **CNI chaining mode** alongside the AWS VPC CNI. VPC CNI handles IP address allocation (each pod gets a VPC IP); Cilium adds eBPF-based network policy enforcement and Hubble observability on top.

**What this gives you:**
- `NetworkPolicy` and `CiliumNetworkPolicy` resources enforced at the kernel level — no iptables chains
- Hubble UI: a real-time service dependency map and per-connection flow log
- L7-aware policy (filter by HTTP method, path, gRPC service) without sidecars

**To fully replace VPC CNI (ENI mode):** set `cni.chainingMode: none`, `ipam.mode: eni`, and remove the `aws-node` DaemonSet from the cluster before applying. This reduces per-pod IP overhead and is recommended for large node counts.

### Kong Gateway OSS

Kong sits in front of your application services and handles cross-cutting API concerns:

- **Rate limiting** — per-consumer or per-IP, configured via `KongPlugin` CRD
- **Authentication** — Globus OIDC via `kong-openid-connect` community plugin
- **Request routing** — path-based, header-based, host-based via `KongRoute` CRD
- **Observability** — per-route request metrics and logs

**Traffic flow:**
```
Internet → AWS NLB → Kong proxy (kong namespace)
                        |-- globus-oidc-api plugin (Bearer token, headless clients)
                        |-- globus-oidc-web plugin (Authorization Code flow, browser UIs)
                        |-- routes to Services via KongRoute
                        └── Service → Pod
```

Kong is fully open source (Apache 2.0). The management GUI (Kong Manager) and some enterprise plugins require a paid Kong Enterprise license, but all routing and plugin capabilities used here are in the OSS version.

### Globus Authentication

This platform uses [Globus Auth](https://www.globus.org/platform/services/auth) as the OIDC identity provider via the community [kong-openid-connect](https://github.com/cuongntr/kong-openid-connect-plugin) plugin installed into a custom Kong image (`docker/kong/Dockerfile`).

Two `KongClusterPlugin` resources are provisioned in `infrastructure/base/kong/globus-jwt-plugin.yaml`:

| Plugin name | `bearer_only` | Use for |
|---|---|---|
| `globus-oidc-api` | `yes` | Headless API clients — MLflow SDK, notebooks, scripts |
| `globus-oidc-web` | `no` | Browser UIs — OpenMetadata, Grafana (future) |

Any team app can opt into Globus auth by adding the annotation to its `Ingress`:

```yaml
annotations:
  konghq.com/plugins: globus-oidc-api   # or globus-oidc-web for browser UIs
```

**Prerequisites before deploying Kong:**

1. Register an application in [Globus Developers](https://app.globus.org/settings/developers) and obtain a `client_id` and `client_secret`.
2. Add `${KONG_IMAGE_REPOSITORY}` (ECR URL) and `${KONG_IMAGE_TAG}` to `cluster-vars`.
3. Add `${GLOBUS_CLIENT_ID}` and `${GLOBUS_CLIENT_SECRET}` to `cluster-secrets`.
4. Build and push the custom Kong image to ECR:

```bash
cd docker/kong
docker build -t <ECR_REGISTRY>/kong-custom:3.9.0 .
docker push <ECR_REGISTRY>/kong-custom:3.9.0
```

---

## Adding a New Application

1. Add the repository names to `ecr_repositories` in each environment's `terraform.tfvars` and re-apply Terraform.
2. Add a `HelmRelease` (and any supporting manifests) under `apps/base/<your-app>/`.
3. Add `../base/<your-app>` to each `apps/<env>/kustomization.yaml` that should run it.
4. Annotate the app's `Ingress` with `konghq.com/plugins: globus-oidc-api` (headless API) or `konghq.com/plugins: globus-oidc-web` (browser UI) to enforce Globus authentication at the gateway.
5. Add `build:<env>` jobs (extending `.build-base`) and `deploy:<env>` jobs to `.gitlab-ci.yml` for the new app, one set per account.

---

## Scaling to Additional AWS Accounts

To add a new environment (e.g., `sandbox`):

1. Copy `terraform/environments/dev/` to `terraform/environments/sandbox/`
2. Update `terraform.tfvars` and `backend.tf` for the new account
3. Run `terraform/bootstrap/main.tf` in the new account
4. Run `terraform apply` in the new environment directory
5. Add the role ARN and ECR registry outputs as GitLab CI variables
6. Add `tf:plan:sandbox`, `tf:apply:sandbox`, `build:sandbox` (extending `.build-base`), and `deploy:sandbox` jobs to `.gitlab-ci.yml`
7. Create `clusters/sandbox/infrastructure.yaml` and `clusters/sandbox/apps.yaml` pointing at `infrastructure/sandbox` and `apps/sandbox` respectively
8. Create `infrastructure/sandbox/kustomization.yaml` (copy from `infrastructure/dev/`)
9. Create `apps/sandbox/kustomization.yaml` (copy from `apps/dev/`)
