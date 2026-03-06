# Required Repo Update — March 16, 2026

## Loki Helm Chart Repository Migration

**Deadline: March 16, 2026**

Grafana is migrating the open-source Loki Helm chart out of the `grafana/loki` repository
into a new community-maintained repository: `grafana-community/helm-charts`. After March 16,
the chart at the original URL will be maintained in maintenance-only mode for Grafana Enterprise
Logs (GEL) customers only. Open-source users who do not migrate will stop receiving new Loki
releases.

---

## What Needs to Change

### 1. `infrastructure/sources/grafana.yaml`

Update the HelmRepository URL:

**Before:**
```yaml
spec:
  url: https://grafana.github.io/helm-charts
```

**After:**
```yaml
spec:
  url: https://grafana-community.github.io/helm-charts
```

This is the only file that needs to change. The HelmRepository is named `grafana` and the
Loki HelmRelease already references it by that name — no changes needed to
`infrastructure/base/loki/helmrelease.yaml` or any Kustomization.

---

## Verification After Applying

Once the change is committed and Flux reconciles (up to 24h based on the source interval, or
force it with `flux reconcile source helm grafana -n flux-system`), confirm the source is
healthy:

```bash
flux get sources helm -n flux-system
```

The `grafana` source should show `Ready` and `True`. If it shows a 404 or connection error,
double-check the new URL is correct and that the repo has been published at that address by
the time you apply.

---

## Context

- Announcement: https://github.com/grafana/loki/issues/20705
- Community forum post: https://community.grafana.com/t/helm-repository-migration-grafana-community-charts/160983
- No chart API or values changes are expected as part of this migration — it is a hosting
  change only. The current pinned version (`6.53.*`) will continue to work from the new URL.
