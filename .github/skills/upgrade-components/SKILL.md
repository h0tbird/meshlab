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
6. **If the user asked for a PR**: create a branch, commit, push, and open a PR
   (see "Creating the PR" below)

## Fetching Latest Versions — Tips

- **GitHub releases — prefer the `gh` CLI over `fetch_webpage`.** It is faster
  and produces compact output. The terminal tool runs `gh` without a TTY, which
  triggers the alternate-screen pager and returns empty output. Always disable
  it explicitly:

  ```bash
  env GH_FORCE_TTY= GH_PAGER= PAGER=cat NO_COLOR=1 \
      gh release list -R <owner>/<repo> -L 5
  ```

  Fetch many repos in a single command using a small shell helper to keep
  output compact and easy to scan.

- **Helm chart versions — `gh` is also faster than ArtifactHub.** The
  ArtifactHub HTML pages are extremely large (tens of thousands of tokens of
  changelog noise). Prefer one of these compact sources:
  - Chart repo's `index.yaml` (e.g. `curl -sL <repo-url>/index.yaml | yq ...`)
  - The chart's `Chart.yaml` on GitHub
  - `gh release list` for the upstream project repo
  Only fall back to `fetch_webpage` against ArtifactHub when no other source
  exists.

- **Latest kubectl** lives at `https://dl.k8s.io/release/stable.txt`
  (note: `cdn.dl.k8s.io` may not resolve from the devcontainer — use `dl.k8s.io`).

- **Latest Go** is in `https://go.dev/dl/?mode=json` (first entry).

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
- **`gh release list` shows pre-releases inline** — the `Latest` label marks the
  newest stable release; do not blindly take the first row. As of 2026-04, both
  Istio (`1.30.0-beta.0`) and Cilium (`1.20.0-pre.1`) had pre-releases newer
  than the latest stable.
- **Note major version upgrades** that may introduce breaking changes
- **Dependencies**: Some components have compatibility requirements (e.g., Kiali version should be compatible with Istio version)

## Creating the PR

When the user requests a PR:

1. Create a branch off `master`, e.g. `upgrade-components-YYYY-MM`.
2. Commit the changes with a structured body listing each bumped component
   (`old -> new`), grouped by file.
3. Push the branch.
4. Open the PR with `gh pr create`. **The `istio/istio` repo is added as a
   workspace remote, so `gh` may pick it as the default upstream and fail with
   `No commits between istio:master and h0tbird:<branch>`. Always pass
   `--repo h0tbird/meshlab --base master --head <branch>` explicitly.**
   Also set `GH_PAGER=cat NO_COLOR=1` so the command does not open the pager.

   ```bash
   env GH_PAGER=cat NO_COLOR=1 gh pr create \
     --repo h0tbird/meshlab --base master --head <branch> \
     --title "Upgrade meshlab components" \
     --body "..."
   ```

5. Use the same summary table format from "Output Format" as the PR body.

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
