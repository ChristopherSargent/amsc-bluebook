# amsc-bluebook — Technology Stack

All technologies, tools, and services used in this repository, with reference links.

---

## Cloud Platform

| Technology | Version / Tier | Reference |
|---|---|---|
| Amazon Web Services (AWS) | — | https://aws.amazon.com |
| Amazon EKS | 1.30 (configurable) | https://docs.aws.amazon.com/eks |
| Amazon ECR | — | https://docs.aws.amazon.com/ecr |
| Amazon VPC | — | https://docs.aws.amazon.com/vpc |
| AWS IAM (OIDC + IRSA) | — | https://docs.aws.amazon.com/iam |
| AWS KMS | — | https://docs.aws.amazon.com/kms |
| Amazon S3 | — | https://docs.aws.amazon.com/s3 |
| Amazon DynamoDB | — | https://docs.aws.amazon.com/dynamodb |
| Amazon Route 53 | — | https://docs.aws.amazon.com/route53 |
| AWS Load Balancer (ALB / NLB) | — | https://docs.aws.amazon.com/elasticloadbalancing |
| Amazon SQS | — | https://docs.aws.amazon.com/sqs |
| Amazon EventBridge | — | https://docs.aws.amazon.com/eventbridge |

---

## Infrastructure as Code

| Technology | Version | Reference |
|---|---|---|
| Terraform | >= 1.6 | https://developer.hashicorp.com/terraform |
| terraform-aws-modules/vpc | ~> 5.0 | https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws |
| terraform-aws-modules/eks | ~> 20.0 | https://registry.terraform.io/modules/terraform-aws-modules/eks/aws |

### Terraform Providers

| Provider | Version | Reference |
|---|---|---|
| hashicorp/aws | ~> 5.0 | https://registry.terraform.io/providers/hashicorp/aws |
| hashicorp/kubernetes | ~> 2.0 | https://registry.terraform.io/providers/hashicorp/kubernetes |
| hashicorp/helm | ~> 2.0 | https://registry.terraform.io/providers/hashicorp/helm |
| fluxcd/flux | ~> 1.3 | https://registry.terraform.io/providers/fluxcd/flux |
| hashicorp/tls | ~> 4.0 | https://registry.terraform.io/providers/hashicorp/tls |

---

## GitOps

| Technology | Version | Reference |
|---|---|---|
| FluxCD | v2 | https://fluxcd.io |
| Flux Kustomize Controller | v2 | https://fluxcd.io/flux/components/kustomize |
| Flux Helm Controller | v2 | https://fluxcd.io/flux/components/helm |
| Flux Source Controller | v2 | https://fluxcd.io/flux/components/source |

---

## CI/CD

| Technology | Version | Reference |
|---|---|---|
| GitLab CI | — | https://docs.gitlab.com/ee/ci |
| GitLab OIDC (AWS auth) | — | https://docs.gitlab.com/ee/ci/cloud_services/aws |
| Docker (build image) | 26 | https://docs.docker.com |
| Docker-in-Docker (dind) | 26 | https://hub.docker.com/_/docker |
| yq (YAML processor) | latest via apk | https://github.com/mikefarah/yq |
| AWS CLI | v2 | https://docs.aws.amazon.com/cli |

---

## Kubernetes Platform Components

All components are deployed via FluxCD HelmReleases into the EKS cluster.

### Networking

| Component | Chart Version | Namespace | Reference |
|---|---|---|---|
| Cilium (eBPF networking + Hubble) | 1.15.x | `kube-system` | https://cilium.io |
| AWS Load Balancer Controller | 1.8.x | `kube-system` | https://kubernetes-sigs.github.io/aws-load-balancer-controller |
| Kong Gateway OSS (Ingress Controller) | ingress 0.22.x | `kong` | https://docs.konghq.com/kubernetes-ingress-controller |
| kong-openid-connect (community plugin) | latest via luarocks | `kong` | https://github.com/cuongntr/kong-openid-connect-plugin |

### Autoscaling

| Component | Chart Version | Namespace | Reference |
|---|---|---|---|
| Karpenter | 1.0.x | `kube-system` | https://karpenter.sh |
| Metrics Server | 3.12.x | `kube-system` | https://github.com/kubernetes-sigs/metrics-server |

### TLS and DNS

| Component | Chart Version | Namespace | Reference |
|---|---|---|---|
| cert-manager | 1.14.x | `cert-manager` | https://cert-manager.io |
| Let's Encrypt (ACME DNS-01) | — | — | https://letsencrypt.org |
| External DNS | 1.14.x | `external-dns` | https://github.com/kubernetes-sigs/external-dns |

### Observability

| Component | Chart Version | Namespace | Reference |
|---|---|---|---|
| kube-prometheus-stack | 58.x | `monitoring` | https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack |
| Prometheus | (bundled) | `monitoring` | https://prometheus.io |
| Grafana | (bundled) | `monitoring` | https://grafana.com |
| Alertmanager | (bundled) | `monitoring` | https://prometheus.io/docs/alerting/latest/alertmanager |
| Loki | 6.x | `monitoring` | https://grafana.com/oss/loki |
| Promtail | (bundled with Loki) | `monitoring` | https://grafana.com/docs/loki/latest/send-data/promtail |

### Backup

| Component | Chart Version | Namespace | Reference |
|---|---|---|---|
| Velero | 11.4.x | `velero` | https://velero.io |
| velero-plugin-for-aws | v1.13.0 | `velero` | https://github.com/vmware-tanzu/velero-plugin-for-aws |

### Data Platform Applications

| Component | Chart Version | Namespace | Reference |
|---|---|---|---|
| MLflow | 0.x (community-charts) | `mlflow` | https://mlflow.org |
| OpenMetadata | 1.x | `openmetadata` | https://open-metadata.org |
| openmetadata-dependencies (Elasticsearch + MySQL) | 1.x | `openmetadata` | https://helm.open-metadata.org |

### Authentication

| Technology | Reference |
|---|---|
| Globus Auth (OIDC identity provider) | https://www.globus.org/platform/services/auth |

### Secrets Management

| Component | Chart Version | Namespace | Reference |
|---|---|---|---|
| External Secrets Operator | 2.0.x | `external-secrets` | https://external-secrets.io |

---

## Helm Chart Repositories

| Name | URL |
|---|---|
| eks-charts | https://aws.github.io/eks-charts |
| jetstack (cert-manager) | https://charts.jetstack.io |
| prometheus-community | https://prometheus-community.github.io/helm-charts |
| grafana | https://grafana.github.io/helm-charts |
| external-dns | https://kubernetes-sigs.github.io/external-dns |
| vmware-tanzu (Velero) | https://vmware-tanzu.github.io/helm-charts |
| karpenter (OCI) | https://public.ecr.aws/karpenter |
| metrics-server | https://kubernetes-sigs.github.io/metrics-server |
| cilium | https://helm.cilium.io |
| kong | https://charts.konghq.com |
| community-charts (MLflow) | https://community-charts.github.io/helm-charts |
| open-metadata | https://helm.open-metadata.org |

---

## Operating System

| Technology | Reference |
|---|---|
| Amazon Linux 2023 (EKS node AMI) | https://aws.amazon.com/linux/amazon-linux-2023 |

---

## Licenses

| Technology | License |
|---|---|
| amsc-bluebook | Apache 2.0 |
| Terraform | BSL 1.1 |
| FluxCD | Apache 2.0 |
| Cilium | Apache 2.0 |
| Kong Gateway OSS | Apache 2.0 |
| kong-openid-connect plugin | MIT |
| MLflow | Apache 2.0 |
| OpenMetadata | Apache 2.0 |
| Globus Auth | Commercial (free tier available) |
| cert-manager | Apache 2.0 |
| External DNS | Apache 2.0 |
| Karpenter | Apache 2.0 |
| Prometheus / Alertmanager | Apache 2.0 |
| Grafana | AGPL 3.0 |
| Loki | AGPL 3.0 |
| Velero | Apache 2.0 |
| External Secrets Operator | Apache 2.0 |
