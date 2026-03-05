# Zarf Init AWS - Flow Documentation

## Overview

This repo provides a custom **Zarf init package** that uses **AWS ECR** (Elastic Container Registry) as the OCI image registry for Zarf-managed Kubernetes deployments on **EKS**. It replaces the default local registry that Zarf ships with, enabling air-gap and semi-connected deployments backed by ECR.

---

## Key Components

| Component | Language | Purpose |
|---|---|---|
| `zarf.yaml` | YAML | Defines the Zarf init package and its four components |
| `capabilities/webhook.ts` + `pepr.ts` | TypeScript (Pepr) | Kubernetes webhook that auto-creates ECR repos during package deploys |
| `main.go` | Go | ECR credential helper binary — refreshes ECR auth tokens in K8s secrets |
| `iam/` | TypeScript (Pulumi) | Provisions IAM roles/policies for the webhook and credential helper |
| `hack/ecr.sh` | Bash | Bootstrap script that creates the initial ECR repo for the Pepr controller |
| `manifests/` | YAML | Kubernetes manifests for the credential helper CronJob |

---

## Architecture

```
EKS Cluster
├── pepr-system namespace
│   └── Pepr Webhook (ecr-hook)          <-- watches Zarf deploy secrets,
│                                             auto-creates ECR repos on-the-fly
└── zarf namespace
    ├── Zarf Agent                        <-- rewrites image refs to ECR
    └── zarf-ecr-credential-helper        <-- CronJob, refreshes ECR tokens hourly
        (optional)

AWS ECR (private or public)
└── Acts as the external OCI registry for all Zarf-managed images
```

---

## End-to-End Flow

### Phase 1: Prerequisites (one-time setup)

1. **EKS cluster** with an IAM OIDC identity provider enabled (required for IRSA — IAM Roles for Service Accounts).

2. **Create IAM roles** for the two in-cluster components:

   | Role | Who uses it | Permissions |
   |---|---|---|
   | `ecr-webhook-role` | Pepr webhook | `ecr:DescribeRepositories`, `ecr:CreateRepository`, `ecr-public:*` equivalents |
   | `ecr-credential-helper-role` | CronJob | `ecr:GetAuthorizationToken` |

   Roles can be created manually using the JSON templates in `iam/json/`, or automatically via Pulumi:

   ```bash
   make create-iam CLUSTER_NAME=my-cluster-name
   ```

   This runs `iam/index.ts` via Pulumi, which calls `iam/utils.ts` to create the policies and roles and attach them together, outputting the role ARNs.

---

### Phase 2: Build the Init Package

```bash
make aws-init-package
# => ZARF_CONFIG="zarf-config.example.yaml" zarf package create -o build ...
```

This compiles the Zarf package defined in `zarf.yaml`. Before building, the Pepr module must be compiled:

```bash
make build-module
# => npm run build && cp dist/pepr-module-*.yaml manifests/
```

The four components bundled into the package are:

1. **`ecr-bootstrap`** (required) — bundles `hack/ecr.sh`
2. **`ecr-hook`** (required) — bundles the compiled Pepr webhook manifest from `manifests/`
3. **`zarf-agent`** (required) — imported from the upstream Zarf skeleton OCI package
4. **`zarf-ecr-credential-helper`** (optional) — bundles `manifests/zarf-ecr-credential-helper.yaml`

---

### Phase 3: Configure and Run `zarf init`

Create a `zarf-config.yaml` specifying your ECR type and IAM role ARNs:

```yaml
architecture: amd64

package:
  deploy:
    components: zarf-ecr-credential-helper   # optional
    set:
      registry_type: private                 # or "public"
      aws_region: us-east-1
      ecr_hook_role_arn: <YOUR_WEBHOOK_ROLE_ARN>
      ecr_credential_helper_role_arn: <YOUR_CREDENTIAL_HELPER_ROLE_ARN>
```

Then run `zarf init`, pointing to ECR as the external registry:

**Private ECR:**
```bash
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

zarf init \
  --registry-url="${AWS_ACCOUNT_ID}.dkr.ecr.<REGION>.amazonaws.com" \
  --registry-push-username="AWS" \
  --registry-push-password="$(aws ecr get-login-password --region <REGION>)" \
  --confirm
```

**Public ECR:**
```bash
zarf init \
  --registry-url="$(aws ecr-public describe-registries --query 'registries[0].registryUri' --output text --region us-east-1)" \
  --registry-push-username="AWS" \
  --registry-push-password="$(aws ecr-public get-login-password --region us-east-1)" \
  --confirm
```

> Note: Public ECR authentication must always use `us-east-1`, regardless of where your cluster runs.

---

### Phase 4: What Happens During `zarf init` Deployment

Zarf deploys each component in order:

#### Step 1 — `ecr-bootstrap` runs `hack/ecr.sh`

- Reads `ZARF_VAR_REGISTRY_TYPE` (private or public) and `ZARF_VAR_AWS_REGION`
- Calls `aws ecr describe-repositories` / `aws ecr create-repository` to ensure the ECR repo `defenseunicorns/pepr/controller` exists
- For private repos: enables `scanOnPush=true` and `IMMUTABLE` tags
- This repository is needed so Zarf can push the Pepr image to ECR before deploying the webhook

#### Step 2 — `ecr-hook` deploys the Pepr webhook

- Applies the kustomized manifests from `manifests/` into the `pepr-system` namespace
- The Pepr controller runs the `ECRhook` capability defined in `capabilities/webhook.ts`
- The webhook ServiceAccount is annotated with the `ecr-webhook-role` ARN via a kustomize patch (`manifests/patches/add-service-account-annotation.patch.yaml`)

#### Step 3 — `zarf-agent` deploys the Zarf mutating webhook

- Imported directly from the upstream Zarf init skeleton OCI package
- Rewrites image references in pod specs to point to the ECR registry URL

#### Step 4 — `zarf-ecr-credential-helper` deploys the token refresh CronJob (if selected)

- Creates a ServiceAccount in the `zarf` namespace annotated with the `ecr-credential-helper-role` ARN (IRSA)
- Deploys a CronJob (default schedule: `0 * * * *` — top of every hour) that runs the Go binary from `main.go`
- The binary: fetches a fresh ECR auth token via `ecr.GetAuthorizationToken`, then scans all namespaces and updates every `private-registry` Kubernetes secret with the new credentials

---

### Phase 5: Ongoing — Pepr Webhook Intercepts Package Deploys

When a subsequent `zarf package deploy` runs on the cluster:

1. Zarf creates/updates a Kubernetes Secret in the `zarf` namespace labeled `package-deploy-info`
2. The Pepr webhook (`capabilities/webhook.ts`) intercepts this via a `MutatingWebhookConfiguration`
3. The webhook:
   - Verifies the Zarf state secret contains a valid ECR registry URL (private pattern: `123456789012.dkr.ecr.<region>.amazonaws.com`, public pattern: `public.ecr.aws/<alias>`)
   - Parses the `DeployedPackage` data from the secret to find images in the component being deployed
   - Sets the webhook status to `Running` (pausing Zarf's deployment of that component)
   - Calls `ECRPrivate.createRepositories()` or `ECRPublic.createRepositories()` (from `capabilities/ecr-private.ts` / `capabilities/ecr-public.ts`) for each image's repository name
   - Updates the webhook status to `Succeeded` or `Failed`, unblocking Zarf to continue

---

### Phase 6: Token Refresh (Ongoing)

ECR auth tokens expire after **12 hours**. The credential helper CronJob runs on schedule to prevent image pull failures:

```
CronJob trigger
  -> main.go runs in-cluster
  -> Reads ECR URL from zarf-state secret
  -> Calls AWS ECR GetAuthorizationToken
  -> Lists all namespaces
  -> For each namespace with a "private-registry" secret (managed by Zarf):
       Updates .dockerconfigjson with the fresh base64-encoded token
```

---

## Variable Reference

| Variable | Where set | Description |
|---|---|---|
| `REGISTRY_TYPE` | `zarf-config.yaml` / prompt | `private` or `public` |
| `AWS_REGION` | `zarf-config.yaml` / prompt | AWS region for ECR (must be `us-east-1` for public) |
| `ECR_HOOK_ROLE_ARN` | `zarf-config.yaml` / prompt | IAM role ARN for the Pepr webhook |
| `ECR_CREDENTIAL_HELPER_ROLE_ARN` | `zarf-config.yaml` / prompt | IAM role ARN for the CronJob |
| `ECR_CREDENTIAL_HELPER_CRON_SCHEDULE` | `zarf-config.yaml` | Cron expression, default `0 * * * *` |

---

## Cleanup

```bash
# Remove Zarf from the cluster
make destroy

# Teardown the EKS cluster
make remove-eks-package

# Delete IAM roles (via Pulumi)
make delete-iam

# Delete ECR repositories
make delete-private-repos   # or delete-public-repos
```

---

## Development Workflow

```bash
# Install dependencies
make install-node-deps

# Make changes to Pepr TypeScript capabilities, then:
make test-module        # run unit tests
make format-ts          # auto-format
make build-module       # recompile and copy manifest to manifests/

# Build the full init package
make aws-init-package

# Regenerate TypeScript types from Zarf Go structs
make gen-schema
```
