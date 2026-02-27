---
name: upgrade-components
description: Upgrades meshlab component versions defined in bin/meshlab (Helm charts) and .devcontainer/Dockerfile (CLI tools) by checking ArtifactHub and GitHub releases for latest versions. Use this skill when asked to upgrade, update, or check versions of Cilium, Istio, Prometheus, Grafana, Vault, cert-manager, Argo CD, Kiali, kind, kubectl, helm, or other infrastructure components and CLI tools.
---

# Meshlab Component Upgrade Skill

This skill helps upgrade the versions of all meshlab infrastructure components defined in two locations:
- `bin/meshlab` - Helm chart versions for deployed components
- `.devcontainer/Dockerfile` - CLI tool versions for the development environment

---

## Part 1: Helm Chart Versions (`bin/meshlab`)

All Helm chart versions are defined in `bin/meshlab` in the **Versions** section (lines 17-32). Each version variable follows this pattern:

```bash
COMPONENT_VERSION='X.Y.Z'  # https://artifacthub.io/packages/helm/...
```

### Helm Charts Managed

| Variable | Component | Version Source |
|----------|-----------|----------------|
| `KINDCCM_VERSION` | cloud-provider-kind | https://github.com/kubernetes-sigs/cloud-provider-kind/releases |
| `CILIUM_CHART_VERSION` | Cilium | https://artifacthub.io/packages/helm/cilium/cilium |
| `K8S_GATEWAY_CHART_VERSION` | k8s-gateway | https://github.com/k8s-gateway/k8s_gateway |
| `ARGOCD_CHART_VERSION` | Argo CD | https://artifacthub.io/packages/helm/argo-cd-oci/argo-cd |
| `ARGOWF_CHART_VERSION` | Argo Workflows | https://artifacthub.io/packages/helm/argo/argo-workflows |
| `PROMETHEUS_CHART_VERSION` | Prometheus | https://artifacthub.io/packages/helm/prometheus-community/prometheus |
| `GRAFANA_CHART_VERSION` | Grafana | https://artifacthub.io/packages/helm/grafana/grafana |
| `OTEL_COLLECTOR_CHART_VERSION` | OpenTelemetry Collector | https://artifacthub.io/packages/helm/opentelemetry-helm/opentelemetry-collector |
| `VAULT_CHART_VERSION` | Vault | https://artifacthub.io/packages/helm/hashicorp/vault |
| `CERT_MANAGER_CHART_VERSION` | cert-manager | https://artifacthub.io/packages/helm/cert-manager/cert-manager |
| `KUBERNETES_REPLICATOR_CHART_VERSION` | kubernetes-replicator | https://artifacthub.io/packages/helm/kubernetes-replicator/kubernetes-replicator |
| `ISTIO_CHART_VERSION` | Istio | https://artifacthub.io/packages/helm/istio-official/base |
| `KIALI_CHART_VERSION` | Kiali Operator | https://artifacthub.io/packages/helm/kiali/kiali-operator |

---

## Part 2: CLI Tool Versions (`.devcontainer/Dockerfile`)

CLI tool versions are defined in `.devcontainer/Dockerfile` using inline `VERSION` variables in RUN commands. Pattern:

```dockerfile
RUN VERSION="X.Y.Z" && ARCH=$(archmap 'arm64' 'amd64') && \
    wget ...
```

### CLI Tools Managed

| Tool | Version Source |
|------|----------------|
| Go | https://go.dev/dl/ |
| kind | https://github.com/kubernetes-sigs/kind/releases |
| kubectl | https://cdn.dl.k8s.io/release/stable.txt |
| helm | https://github.com/helm/helm/releases |
| yq | https://github.com/mikefarah/yq/releases |
| argocd | https://github.com/argoproj/argo-cd/releases |
| argo (workflows) | https://github.com/argoproj/argo-workflows/releases |
| cilium-cli | https://github.com/cilium/cilium-cli/releases |
| istioctl | https://github.com/istio/istio/releases |
| step | https://github.com/smallstep/cli/releases |
| gh | https://github.com/cli/cli/releases |
| mdbook | https://github.com/rust-lang/mdBook/releases |
| swarmctl | https://github.com/h0tbird/k-swarm/releases |
| btop | https://github.com/aristocratos/btop/releases |
| tilt | https://github.com/tilt-dev/tilt/releases |
| crane | https://github.com/google/go-containerregistry/releases |
| grafanactl | https://github.com/grafana/grafanactl/releases |

---

## Upgrade Workflow

1. **Read current versions** from both `bin/meshlab` and `.devcontainer/Dockerfile`
2. **Check latest versions** by fetching from ArtifactHub or GitHub releases
3. **Compare versions** and identify components needing upgrades
4. **Present summary** showing current vs latest versions before making changes
5. **Apply updates** preserving the formatting in each file

## Formatting Rules

### For `bin/meshlab`:
- Keep the `#` comment with URL on the same line
- Maintain spacing alignment (use spaces to align comments)
- Preserve any version prefixes (e.g., `v1.19.2` for cert-manager)

Example:
```bash
GRAFANA_CHART_VERSION='10.6.0'                # https://artifacthub.io/packages/helm/grafana/grafana
```

### For `.devcontainer/Dockerfile`:
- Keep `VERSION=` on same line as `RUN`
- Preserve version format (some use `v` prefix, some don't)
- Don't change architecture mappings or download URLs (only version numbers)

Example:
```dockerfile
RUN VERSION="v0.32.0" && ARCH=$(archmap 'arm64' 'amd64') && \
```

## Important Considerations

- **Prefer stable releases** over pre-release/alpha/beta/RC versions for all components
- **Stay on current stable series**: When the latest version of a component is a pre-release (RC/alpha/beta), stay on the current stable major.minor series and check for the latest patch version in that series (e.g., if latest Cilium is 1.19.0-rc.1, check for the latest 1.18.x stable release)
- **Note major version upgrades** that may introduce breaking changes
- **Dependencies**: Some components have compatibility requirements (e.g., Kiali version should be compatible with Istio version)

## Output Format

Provide a summary after upgrades:

### Helm Charts (bin/meshlab)
| Component | Previous | Latest | Status |
|-----------|----------|--------|--------|
| Cilium | 1.18.6 | 1.19.0 | ✅ Upgraded |

### CLI Tools (.devcontainer/Dockerfile)
| Tool | Previous | Latest | Status |
|------|----------|--------|--------|
| kind | v0.31.0 | v0.32.0 | ✅ Upgraded |

Include notes about breaking changes or skipped components.
