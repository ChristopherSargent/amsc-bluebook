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
