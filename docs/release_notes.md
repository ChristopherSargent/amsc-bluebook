# amsc-bluebook — Release Notes

---

## cl4.004 — Resource limits, stale comment removal, and first-boot documentation

### Bug Fixes

- **Missing memory limits on cert-manager, external-dns, metrics-server, and Cilium HelmReleases**
  (`infrastructure/base/cert-manager/helmrelease.yaml`,
  `infrastructure/base/external-dns/helmrelease.yaml`,
  `infrastructure/base/metrics-server/helmrelease.yaml`,
  `infrastructure/base/cilium/helmrelease.yaml`)
  These four HelmReleases had no memory limits (cert-manager, external-dns, metrics-server had
  no `resources:` block at all; Cilium had requests but no limits). Without limits, a memory leak
  or traffic spike in any of these pods can exhaust node memory and trigger evictions of
  co-located workloads. Added `requests` and `limits` to the three missing components and
  added `limits.memory: 512Mi` to Cilium alongside its existing requests.

- **Stale development comment in `staging/main.tf`**
  (`terraform/environments/staging/main.tf`)
  The file header contained `# Copy dev/main.tf here and update the two values below.` — a
  leftover editing artifact. The file is complete; no copying is needed. On a reference
  implementation this reads as an instruction to the reader and was removed.

### Documentation

- **First-boot CRD timing not documented**
  (`README.md`)
  Karpenter's `EC2NodeClass` and `NodePool` and cert-manager's `ClusterIssuer` are applied in
  the same Kustomization as their respective HelmReleases. On first boot the CRDs those resources
  require don't exist yet, so Flux logs errors for ~10 minutes until the HelmReleases finish
  installing the CRDs and the next reconciliation cycle succeeds. This is self-healing but
  alarming if unexpected. Added a callout block to Step 3 explaining the behaviour and the
  `flux get kustomizations -A` command to monitor it.

### Updated Files

| File | Change |
|---|---|
| `infrastructure/base/cert-manager/helmrelease.yaml` | Add `resources.requests` (cpu: 50m, memory: 64Mi) and `resources.limits` (memory: 128Mi) |
| `infrastructure/base/external-dns/helmrelease.yaml` | Add `resources.requests` (cpu: 10m, memory: 64Mi) and `resources.limits` (memory: 128Mi) |
| `infrastructure/base/metrics-server/helmrelease.yaml` | Add `resources.requests` (cpu: 100m, memory: 64Mi) and `resources.limits` (memory: 128Mi) |
| `infrastructure/base/cilium/helmrelease.yaml` | Add `resources.limits.memory: 512Mi` alongside existing requests |
| `terraform/environments/staging/main.tf` | Remove stale `# Copy dev/main.tf here...` comment |
| `README.md` | Add first-boot CRD timing callout to Step 3 |

---

## cl4.004 — Documentation: repo structure and provider lock file guidance

### Documentation

- **Repo structure diagram omitted `infrastructure/dev/`, `infrastructure/staging/`, `infrastructure/prod/`**
  (`README.md`)
  The repository structure diagram showed only `infrastructure/sources/` and `infrastructure/base/`.
  The three environment kustomization directories were missing despite being the actual Flux
  reconciliation targets (each `clusters/<env>/infrastructure.yaml` points at `infrastructure/<env>`).
  `infrastructure/prod/` additionally contains the Loki S3 patch critical to prod log durability.
  Added all three directories to the diagram with descriptions, including `infrastructure/prod/patches/loki-s3.yaml`.

- **Step 3b lacked the `terraform providers lock` command**
  (`README.md`)
  Step 3b said "commit the generated lock file" without showing how to generate it.
  Added the `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` invocation
  for each environment directory, with a note to add `-platform=` flags for all OS/arch combinations
  in use locally and in CI.

### Updated Files

| File | Change |
|---|---|
| `README.md` | Added `infrastructure/dev/`, `infrastructure/staging/`, `infrastructure/prod/patches/` to repo structure diagram; added `terraform providers lock` command to Step 3b |

---

## cl4.004 — Security hardening, reliability, and CI correctness pass

### Bug Fixes

- **Karpenter IRSA not created — wrong input variable name on karpenter submodule**
  (`terraform/environments/*/platform.tf`)
  The karpenter submodule (`terraform-aws-modules/eks/aws//modules/karpenter` v20) uses
  `oidc_provider_arn` as the OIDC provider input. The code passed `irsa_oidc_provider_arn`,
  which does not exist in v20 and causes an immediate Terraform error:
  "An argument named 'irsa_oidc_provider_arn' is not expected here."
  This prevented `terraform apply` from completing in all three environments.
  Fixed: renamed to `oidc_provider_arn` in all three platform files.

- **CI Terraform cache key was empty for plan/validate jobs**
  (`.gitlab-ci.yml`)
  The `.terraform` base template used `key: terraform-${CI_ENVIRONMENT_NAME}` for caching.
  `CI_ENVIRONMENT_NAME` is only set when a job declares `environment:`, which only the
  `apply` jobs do — plan and validate jobs resolved to an empty cache key.
  Fixed: changed to `key: terraform-${ENV}`, which is set via `variables:` in every job.

- **CI deploy job corrupted YAML with `sed`; `yq` path targeted wrong YAML level**
  (`.gitlab-ci.yml`)
  `sed -i "s|tag:.*|tag: ${CI_COMMIT_SHORT_SHA}|"` had two bugs: it matched any YAML
  key named `tag:` (not only `image.tag`), and it stripped leading whitespace from the
  matched line, producing invalid YAML indentation. Replaced with `yq`. Additionally, the
  initial `yq` path `.image.tag` targeted the document root rather than the correct
  `spec.values.image.tag` path inside the HelmRelease manifest. Fixed to
  `yq -i ".spec.values.image.tag = strenv(CI_COMMIT_SHORT_SHA)" clusters/${DEPLOY_ENV}/apps/myapp.yaml`.
  The target filename is now `myapp.yaml` (the HelmRelease) instead of `myapp-values.yaml`.
  The deploy base image (`alpine/git`) gains a `before_script` step to install `yq` via `apk`.

- **CI build job only pushed to dev ECR; staging and prod could not pull the image**
  (`.gitlab-ci.yml`)
  The single `build` job assumed `$DEV_TF_ROLE_ARN` and pushed only to `$DEV_ECR_REGISTRY`.
  Since each environment is a separate AWS account with its own ECR registry, nodes in
  staging and prod had no access to the image. The `build` job has been split into three
  jobs extending a shared `.build-base` template:
  - `build:dev` — assumes `$DEV_TF_ROLE_ARN`, pushes to `$DEV_ECR_REGISTRY`, runs auto on `main`
  - `build:staging` — assumes `$STAGING_TF_ROLE_ARN`, pushes to `$STAGING_ECR_REGISTRY`, manual
  - `build:prod` — assumes `$PROD_TF_ROLE_ARN`, pushes to `$PROD_ECR_REGISTRY`, manual on tags
  Each `deploy:<env>` now gates on its corresponding `build:<env>` via `needs:`.

### Security

- **KMS key deletion window was 7 days in all environments**
  (`terraform/modules/eks/main.tf`, `terraform/modules/ecr/main.tf`)
  AWS recommends 30 days for production KMS keys to allow time to detect and recover
  from accidental deletion before the key is permanently destroyed. Changed
  `deletion_window_in_days` from `7` to `30` in both the EKS secrets KMS key and the
  ECR encryption KMS key.

- **No destruction protection on critical persistent resources**
  (`terraform/modules/eks/main.tf`, `terraform/modules/ecr/main.tf`,
  `terraform/environments/*/platform.tf`)
  A `terraform destroy` in the wrong environment would permanently delete KMS keys and
  backup buckets. Added `lifecycle { prevent_destroy = true }` to:
  - `aws_kms_key.eks_secrets` — EKS secrets envelope encryption key
  - `aws_kms_key.ecr` — ECR image encryption key
  - `aws_s3_bucket.velero` — backup storage (all three environments)
  - `aws_s3_bucket.loki` — log storage (all three environments, new resource)

### Reliability

- **Loki used ephemeral filesystem storage in all environments**
  (`infrastructure/base/loki/helmrelease.yaml`, `infrastructure/prod/`)
  The base HelmRelease used `storage.type: filesystem` with a single-binary replica.
  A pod restart or rescheduling permanently deleted all log data. In prod this is
  unacceptable. The fix has two parts:

  1. **Terraform** (`terraform/environments/*/platform.tf`): A dedicated Loki S3 bucket
     is provisioned in all three environments (KMS-encrypted, versioned, public access
     blocked, 30-day noncurrent version expiry). An IRSA role for the `loki` service
     account in `monitoring` is created with scoped S3 read/write permissions.
     `LOKI_ROLE_ARN` and `LOKI_BUCKET` are added to the `cluster-vars` ConfigMap so
     Flux HelmReleases can consume them via `substituteFrom`.

  2. **Flux** (`infrastructure/prod/patches/loki-s3.yaml`,
     `infrastructure/prod/kustomization.yaml`): A kustomize strategic merge patch is
     applied on top of the base HelmRelease in prod only. It switches Loki to
     `deploymentMode: SimpleScalable` with 3 write replicas, 2 read replicas, and 2
     backend replicas backed by the S3 bucket. The IRSA annotation on the service
     account allows S3 access without static credentials. Dev and staging continue to
     use the filesystem mode (no operational impact).

- **Velero S3 bucket accumulated noncurrent object versions indefinitely**
  (`terraform/environments/*/platform.tf`)
  Versioning was enabled on the Velero bucket but no lifecycle rule expired old versions.
  With frequent backup cycles, orphaned object versions accumulated without bound.
  Added `aws_s3_bucket_lifecycle_configuration.velero` with a 90-day noncurrent version
  expiration rule to all three environments, consistent with the state bucket.

### Maintainability

- **Kubernetes version was hardcoded in all three `main.tf` files**
  (`terraform/environments/*/main.tf`, `terraform/environments/*/variables.tf`,
  `terraform/environments/*/terraform.tfvars`)
  `cluster_version = "1.30"` was a literal in each environment's `main.tf`. Upgrading
  Kubernetes required editing three source files. Added a `cluster_version` input variable
  to all three environments with a default of `"1.30"`. The value is set explicitly in
  each `terraform.tfvars` so it is visible and overridable without touching module code.

- **Provider lock files not committed**
  (`terraform/.gitignore` already excluded `.terraform.lock.hcl` from ignoring)
  Without committed lock files, `terraform init` on a fresh CI runner resolves provider
  versions from scratch and may pull different patch releases, making builds
  non-reproducible. Added Step 2b to the README setup guide documenting how to generate
  and commit lock files after the first `terraform init`.

### Updated Files

| File | Change |
|---|---|
| `.gitlab-ci.yml` | Split `build` into `.build-base` + `build:dev/staging/prod`; yq replace sed in `.deploy`; fixed yq path to `.spec.values.image.tag` and target file to `myapp.yaml`; update `needs:` on all deploy jobs; fix stale `CONFIG_REPO_PATH` comment; fix Terraform cache key `${CI_ENVIRONMENT_NAME}` → `${ENV}` |
| `infrastructure/sources/karpenter.yaml` | `apiVersion` `v1beta2` → `v1` (consistent with all other sources) |
| `terraform/environments/dev/terraform.tfvars` | `config_repo_path` placeholder updated to `my-org/amsc-bluebook` |
| `terraform/environments/staging/terraform.tfvars` | Same |
| `terraform/environments/prod/terraform.tfvars` | Same |
| `terraform/environments/dev/variables.tf` | `config_repo_path` description updated to reference this repo |
| `terraform/environments/staging/variables.tf` | Same |
| `terraform/environments/prod/variables.tf` | Same |
| `terraform/environments/dev/platform.tf` | Fix stale section 7 Loki comment; fix karpenter `irsa_oidc_provider_arn` → `oidc_provider_arn`; plus earlier changes |
| `terraform/environments/staging/platform.tf` | Same |
| `terraform/environments/prod/platform.tf` | Same |
| `terraform/modules/eks/main.tf` | `deletion_window_in_days` 7→30; `lifecycle.prevent_destroy = true` on KMS key |
| `terraform/modules/ecr/main.tf` | `deletion_window_in_days` 7→30; `lifecycle.prevent_destroy = true` on KMS key |
| `terraform/environments/dev/main.tf` | `cluster_version = var.cluster_version` |
| `terraform/environments/dev/variables.tf` | Add `cluster_version` variable |
| `terraform/environments/dev/terraform.tfvars` | Add `cluster_version = "1.30"` |
| `terraform/environments/dev/platform.tf` | `prevent_destroy` on Velero bucket; Velero lifecycle rule; Loki S3 bucket + IRSA; `LOKI_ROLE_ARN`/`LOKI_BUCKET` in cluster-vars |
| `terraform/environments/staging/main.tf` | `cluster_version = var.cluster_version` |
| `terraform/environments/staging/variables.tf` | Add `cluster_version` variable |
| `terraform/environments/staging/terraform.tfvars` | Add `cluster_version = "1.30"` |
| `terraform/environments/staging/platform.tf` | Same as dev |
| `terraform/environments/prod/main.tf` | `cluster_version = var.cluster_version` |
| `terraform/environments/prod/variables.tf` | Add `cluster_version` variable |
| `terraform/environments/prod/terraform.tfvars` | Add `cluster_version = "1.30"` |
| `terraform/environments/prod/platform.tf` | Same as dev |
| `infrastructure/prod/patches/loki-s3.yaml` | New — Loki S3 SimpleScalable patch for prod |
| `infrastructure/prod/kustomization.yaml` | Add `patches:` block referencing `loki-s3.yaml` |
| `README.md` | Updated platform table, env differences table, CI pipeline reference, module reference, setup guide; fixed config repo relationship, added Route53 prerequisite, fixed Step 4 variables split by repo, added Loki IRSA to Step 3 bullet list, fixed Step 5 example (v1beta2→v1), added Helm chart OCI prerequisite note to Step 5, fixed ESO description (no ExternalSecret configured — nodes use instance role for ECR), fixed day-to-day flow, fixed CI repo split note, corrected yq path |

---

## cl4.002 — Third review pass: deprecations, missing values, housekeeping, LICENSE

### Errors Fixed

- **`letsencrypt_email` missing from all three `terraform.tfvars`**
  The variable was added in the prior review pass but never added to the tfvars files.
  Because it has no default, `terraform plan` would fail with "No value for required
  variable" in CI or prompt interactively. Added a placeholder with a clear comment to
  all three environment tfvars files.

- **All nine `HelmRepository` sources used deprecated `v1beta2` API version**
  `source.toolkit.fluxcd.io/v1beta2` was superseded by `v1` in Flux 2.3 and is
  scheduled for removal. Updated all nine source files to `source.toolkit.fluxcd.io/v1`.

### Security / Production

- **Bootstrap S3 bucket had no lifecycle policy**
  With versioning enabled but no lifecycle rule, old state file versions accumulated
  indefinitely. Added a 90-day noncurrent version expiration rule to `bootstrap/main.tf`.

- **LICENSE copyright notice had unfilled template text**
  The copyright line still read `Copyright [yyyy] [name of copyright owner]` — the
  boilerplate from the Apache 2.0 appendix was never filled in. Updated to credit
  Defense Unicorns for the original work and contributors for subsequent work.

### Housekeeping

- **`CODEOWNERS` removed**
  Referenced the original Defense Unicorns team (`@Racer159`, `@Noxsios`, `@jeff-mccoy`,
  etc.) who have no relationship to this fork. Leaving a CODEOWNERS file with stale
  names blocks merge requests by requiring approvals from people who don't have access.

### LICENSE Decision

Apache 2.0 is retained and the copyright updated to **American Science Cloud (AmSC)**.

Apache 2.0 is the correct choice for this project because:
- The platform will be shared openly across institutions, national labs, and federal
  partners working on scientific computing infrastructure
- Apache 2.0's explicit **patent grant** protects all downstream users — if any
  contributor later asserts patent rights over their contribution, their Apache 2.0
  license automatically terminates, preventing patent ambush
- Federal agencies and programs (NSF ACCESS, DOE, NIH) commonly pre-approve Apache 2.0
  in their open-source policies, simplifying legal review for institutional adoption
- MIT would be equally permissive but provides no patent protection — a meaningful gap
  when multiple organisations and government contractors contribute

Copyright line:
```
Copyright 2024 Defense Unicorns (original work)
Copyright 2025 American Science Cloud (AmSC)
```

---

## cl4.002 — Add Cilium (eBPF networking) and Kong Gateway OSS

### New Components

- **Cilium** (`infrastructure/base/cilium/`)
  Cilium is added in CNI chaining mode alongside the AWS VPC CNI. VPC CNI continues
  to handle IP address allocation (each pod gets a real VPC IP); Cilium layers eBPF
  on top to provide kernel-level network policy enforcement and Hubble observability.
  No sidecar proxies are required.

  Key configuration:
  - `cni.chainingMode: aws-cni` — works alongside VPC CNI, no disruption to existing networking
  - `ipam.mode: kubernetes` — delegates IP management to Kubernetes/VPC CNI
  - `hubble.relay.enabled: true` + `hubble.ui.enabled: true` — real-time service
    dependency map and per-flow traffic visibility via the Hubble UI
  - To fully replace the VPC CNI with Cilium ENI mode, set `cni.chainingMode: none`
    and `ipam.mode: eni` and remove the `aws-node` DaemonSet

  Source: `infrastructure/sources/cilium.yaml` (`https://helm.cilium.io/`)

- **Kong Gateway OSS** (`infrastructure/base/kong/`)
  Kong Ingress Controller (KIC) is added as an API gateway in front of application
  services. Kong handles L7 concerns (rate limiting, authentication, request routing)
  that the AWS Load Balancer Controller does not provide natively.

  Key configuration:
  - `gateway.proxy.type: LoadBalancer` with NLB annotations — AWS LBC provisions an
    NLB in front of Kong's proxy port
  - `gateway.admin.type: ClusterIP` — admin API is not exposed externally
  - `gateway.replicaCount: 2` — HA for the proxy
  - Kong is fully open source (Apache 2.0); the management GUI requires Kong Enterprise
  - Routes and plugins are managed via `KongRoute`, `KongService`, and `KongPlugin` CRDs

  Source: `infrastructure/sources/kong.yaml` (`https://charts.konghq.com`)

### Updated Files

- `infrastructure/sources/kustomization.yaml` — added `cilium.yaml` and `kong.yaml`
- `infrastructure/dev/kustomization.yaml` — added `../base/cilium` and `../base/kong`
- `infrastructure/staging/kustomization.yaml` — same
- `infrastructure/prod/kustomization.yaml` — same
- `README.md` — updated architecture diagram, added platform components table,
  added Cilium + Kong networking section, fixed example HelmRelease to use `v2` API

---

## cl4.002 — Production review: error fixes, security hardening, quality improvements

### Errors Fixed

- **`amiFamily: AL2` → `AL2023`** (`infrastructure/base/karpenter/ec2nodeclass.yaml`)
  Amazon Linux 2 reached end-of-life June 2025. Karpenter would fail to launch nodes
  because the AL2 EKS-optimized AMI is no longer published. Changed to `AL2023`.

- **Kong CRDs never installed** (`infrastructure/base/kong/helmrelease.yaml`)
  `installCRDs: false` was set with no separate mechanism to apply them. The Kong
  Ingress Controller would crash immediately because `KongRoute`, `KongService`, and
  `KongPlugin` CRDs were missing. Changed to `installCRDs: true`.

- **Kong Helm value key paths wrong** (`infrastructure/base/kong/helmrelease.yaml`)
  The values structure did not match the `kong/ingress` chart schema:
  - `controller.ingressController` → top-level `ingressController`
  - `gateway.admin.type` → `gateway.admin.service.type`
  - `gateway.proxy.type` / `gateway.proxy.annotations` → `gateway.proxy.service.type` / `gateway.proxy.service.annotations`
  The gateway would have deployed with wrong service types and no NLB.

### Security

- **EKS private endpoint enabled** (`terraform/modules/eks/main.tf`)
  `cluster_endpoint_private_access: true` added alongside the existing public endpoint.
  Nodes and in-VPC callers (including Flux and Karpenter) now reach the API server
  without traversing the public internet. The public endpoint remains for CI runners
  outside the VPC, restricted by `cluster_endpoint_public_access_cidrs`.

- **ECR customer-managed KMS key** (`terraform/modules/ecr/main.tf`)
  `encryption_type = "KMS"` previously used the AWS-managed ECR key, which cannot be
  rotated on a custom schedule or audited independently. ECR repositories now use a
  dedicated CMK with automatic key rotation, consistent with the EKS secrets KMS key.

- **`terraform/.gitignore` secret file conventions clarified**
  Documented that `terraform.tfvars` is intentionally not ignored (non-sensitive config
  only). Added `*.secrets.tfvars` as the convention for files containing sensitive
  values. All sensitive inputs must be passed via `TF_VAR_*` environment variables.

### Production Quality

- **cert-manager email no longer hardcoded** (`infrastructure/base/cert-manager/clusterissuer.yaml`)
  `platform@example.com` was a placeholder that would silently prevent Let's Encrypt
  from sending expiry warnings. Replaced with `${LETSENCRYPT_EMAIL}` substitution
  variable. Added `letsencrypt_email` input variable to all three environments and
  wired it into the `cluster-vars` ConfigMap.

- **GitLab CI: `tf:apply:dev` now has an `environment:` block**
  Staging and prod apply jobs had `environment:` blocks; dev did not. Without it,
  GitLab does not track dev as a deployment environment, cannot display environment
  status, and deployment protection rules cannot be applied.

- **GitLab CI: deploy jobs now declare `needs: [build]`**
  Without explicit `needs:`, deploy jobs would block until every job in all prior
  stages completed — including unrelated manual `tf:plan:staging` and `tf:plan:prod`
  jobs. The three deploy jobs now run as soon as the image build completes.

- **`cluster-secrets` marked `optional: true` in all Flux Kustomizations**
  (`clusters/dev/infrastructure.yaml`, `clusters/staging/`, `clusters/prod/`)
  If Flux reconciles during the first `terraform apply` before `kubernetes_secret`
  has been written, it would hard-fail. With `optional: true` it retries on the
  next interval instead.

- **Memory limits added to all HelmReleases**
  Components with only `requests` set (Karpenter controller, Prometheus, Loki) now
  also have `limits`. Without limits, a memory leak or traffic spike can exhaust node
  memory and trigger pod evictions across the node.

- **Velero AWS plugin bumped** (`infrastructure/base/velero/helmrelease.yaml`)
  `velero/velero-plugin-for-aws:v1.9.0` → `v1.10.0` to pick up upstream bug fixes.

- **`outputs.tf` improved across all three environments**
  Added `ecr_registry` (the hostname needed for `DEV/STAGING/PROD_ECR_REGISTRY`
  GitLab variables) and `kms_key_arn` outputs. `terraform output` now returns
  everything the README setup guide asks for without manual calculation.

---

## cl4.001 — Security hardening, bug fixes, and production quality pass

### Security

- **Grafana admin password moved out of ConfigMap into Kubernetes Secret**
  Previously `GRAFANA_ADMIN_PASSWORD` was stored in the `cluster-vars` ConfigMap.
  ConfigMaps are base64-encoded plaintext — readable by anyone with `kubectl get cm`
  or sufficient RBAC access. The password is now stored in a `kubernetes_secret`
  resource (`cluster-secrets` in `flux-system`) which is encrypted at rest via the
  KMS key used for EKS secrets envelope encryption. Flux `substituteFrom` was updated
  in all three clusters to pull from both the ConfigMap (non-sensitive ARNs) and the
  Secret (sensitive values). HelmReleases are unchanged — `${GRAFANA_ADMIN_PASSWORD}`
  still works but the value is no longer visible in plaintext.

### Bug Fixes

- **Flux provider HCL syntax error (all three environments)**
  The `provider "flux"` block in `dev/providers.tf`, `staging/providers.tf`, and
  `prod/providers.tf` used object attribute syntax (`kubernetes = { ... }`,
  `exec = { ... }`, `git = { ... }`) instead of the HCL nested block syntax that
  the `fluxcd/flux` provider v1.3 requires. This would have caused a Terraform parse
  error on `terraform init`. All three files have been corrected to use block syntax.

- **Karpenter 1.0 chart source was wrong**
  The Karpenter HelmRelease pointed at the `eks-charts` HelmRepository for chart
  version `1.0.*`. Karpenter 1.0+ moved to an OCI registry (`public.ecr.aws/karpenter`)
  and is no longer published to eks-charts (which only carries 0.x). Flux would fail
  to resolve the chart. A new `infrastructure/sources/karpenter.yaml` OCI HelmRepository
  has been added, and the HelmRelease updated to reference it.

- **metrics-server pointed at eks-charts instead of official source**
  The canonical metrics-server Helm chart for version `3.12.*` is maintained at
  `kubernetes-sigs.github.io/metrics-server`. The eks-charts copy may not carry
  this version. A dedicated `infrastructure/sources/metrics-server.yaml` HelmRepository
  has been added pointing to the official source, and the HelmRelease updated accordingly.

- **All HelmReleases used deprecated API version `v2beta1`**
  `helm.toolkit.fluxcd.io/v2beta1` was deprecated in Flux 2.2 and removed in Flux 2.4.
  All seven HelmReleases have been updated to `helm.toolkit.fluxcd.io/v2`.

- **Missing namespace creation in HelmReleases**
  HelmReleases deploying into `cert-manager`, `external-dns`, `monitoring`, and `velero`
  namespaces would fail with "namespace not found" because Flux does not auto-create
  namespaces. Added `install.createNamespace: true` to cert-manager, external-dns,
  kube-prometheus-stack, loki, and velero HelmReleases.

### Portability

- **CI deploy job hardcoded `gitlab.com` hostname**
  The `.deploy` job template cloned the config repo using a hardcoded `gitlab.com`
  URL. This would fail on self-hosted GitLab instances. Changed to `${CI_SERVER_HOST}`
  which GitLab injects automatically.

- **CI OIDC token audience hardcoded to `https://gitlab.com`**
  The `id_tokens` OIDC audience was set to a literal `https://gitlab.com`. For
  self-hosted GitLab this would not match the instance URL, causing AWS STS to reject
  the token. It would also mismatch the `client_id_list` on the
  `aws_iam_openid_connect_provider` resource which uses `var.gitlab_url`. Changed to
  `$CI_SERVER_URL` which GitLab sets to the instance URL automatically.

### Cleanup

- **`.gitignore` updated**
  Removed stale patterns left over from the original Zarf/Pulumi codebase
  (`Pulumi.**.y*ml`, `zarf-config.y*ml`, `zarf-sbom`, `eks.yaml`, `**.tar.zst`).
  Added `Version1.md` (conversation artifact) and `*.tfvars.local`.

---

## Prior commits on this branch

### 7b6a3c6 — Fix 3 bugs and add 8 platform components via Flux HelmReleases

- Fixed `terraform/.gitignore` to stop ignoring `.terraform.lock.hcl`
  (lock files must be committed for reproducible provider pinning)
- Added KMS key for EKS secrets envelope encryption to the EKS module
- Added `cluster_endpoint_public_access_cidrs` variable to restrict API server access
- Added IRSA roles for all 8 cluster add-ons: AWS Load Balancer Controller, Karpenter
  (with SQS interruption queue), cert-manager, External DNS, Velero
- Added Velero S3 bucket with KMS encryption, versioning, and public access block
- Added `cluster-vars` ConfigMap — Terraform writes all ARNs/values; Flux consumes
  them via `substituteFrom` eliminating manual ARN copying
- Added Flux HelmReleases for all 8 components with correct IRSA annotations and
  variable substitution placeholders

### d8a694b — Remove stale Zarf/Pepr/Pulumi files and rewrite README

- Deleted all Zarf package manifests, Pepr webhook TypeScript, Pulumi IAM code,
  Go binaries, and GitHub Actions workflows
- Rewrote `README.md` with architecture overview, setup guide, environment comparison
  table, module reference, and CI pipeline reference

### 451048a — Add new AWS multi-account stack

- Initial Terraform module structure: `modules/eks`, `modules/ecr`, `modules/irsa`,
  `bootstrap/`
- Per-environment root modules: `environments/dev`, `environments/staging`,
  `environments/prod` with separate VPC CIDRs, node sizes, and OIDC trust conditions
- GitLab CI pipeline: OIDC-based AWS auth (no static credentials), validate/plan/apply
  stages, ECR build and GitOps deploy jobs
- Flux GitRepository + Kustomization layout: `clusters/`, `infrastructure/base/`,
  `infrastructure/sources/`
