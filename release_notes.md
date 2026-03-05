# Release Notes

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
