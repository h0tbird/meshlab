---
name: upgrade-components
description: Upgrades meshlab component versions defined in bin/meshlab (Helm charts) and .devcontainer/Dockerfile (CLI tools) by checking ArtifactHub and GitHub releases for latest versions. Use this skill when asked to upgrade, update, or check versions of Istio, Prometheus, Grafana, Vault, cert-manager, Argo CD, Kiali, kind, kubectl, helm, or other infrastructure components and CLI tools.
---

# Meshlab Component Upgrade Skill

This skill helps upgrade the versions of all meshlab infrastructure components defined in these locations:
- `bin/meshlab` - Helm chart versions for deployed components
- `.devcontainer/Dockerfile` - CLI tool versions for the development environment
- `Tiltfile` - Istio version pinned for the `pilot-discovery` live-reload dev loop (must be bumped in lockstep with `ISTIO_CHART_VERSION`)

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

Two copy-paste blocks below check **every** component in one shot. Run them
verbatim — they encode the gotchas learned the hard way, so don't re-derive
the commands (that is what wastes tokens). Then `kubectl`/`Go` are two extra
one-liners.

### Block 1 — all GitHub-release components (one batch call)

The `--json`/`-q` filter selects the entry flagged `isLatest`, so it skips
pre-releases automatically — no need to eyeball the `Latest` label.

```bash
env GH_FORCE_TTY= GH_PAGER= PAGER=cat NO_COLOR=1 bash -c '
for repo in \
  kubernetes-sigs/cloud-provider-kind k8s-gateway/k8s_gateway \
  argoproj/argo-cd argoproj/argo-workflows hashicorp/vault \
  cert-manager/cert-manager mittwald/kubernetes-replicator \
  kubernetes-sigs/metrics-server istio/istio kiali/kiali \
  kubernetes-sigs/kind helm/helm mikefarah/yq \
  smallstep/cli cli/cli rust-lang/mdBook h0tbird/k-swarm \
  aristocratos/btop tilt-dev/tilt google/go-containerregistry \
  grafana/grafanactl sharkdp/bat; do
  echo -n "$repo: "
  gh release list -R $repo -L 8 --json tagName,isLatest \
    -q "[.[] | select(.isLatest)] | .[0].tagName // \"(none)\"" 2>/dev/null
done'
```

### Block 2 — Helm chart versions from each repo's `index.yaml`

`gh`/`index.yaml` are far cheaper than ArtifactHub (whose HTML is tens of
thousands of tokens of changelog noise). **yq gotchas that cost retries last
time — get them right the first time:**
- yq has **no `-r` flag** (that's jq). Plain `yq '...'` already prints raw.
- For case-insensitive regex use `test("(?i)pattern")`. Do **not** use the
  jq-style `test("pattern";"i")` — yq rejects the `"i"` option arg.
- Entries are already sorted newest-first, so `.[0]` after filtering = latest.
- Fetch each chart **individually** (one `curl … | yq` per line). A single
  loop over many large `index.yaml` files truncated its output last time and
  forced re-runs.

```bash
f='map(select(.version | test("(?i)-(rc|alpha|beta|pre|dev|snapshot)") | not)) | .[0].version'
echo "k8s-gateway:           $(curl -sL https://k8s-gateway.github.io/k8s_gateway/index.yaml               | yq ".entries.\"k8s-gateway\" | $f")"
echo "argo-cd:               $(curl -sL https://argoproj.github.io/argo-helm/index.yaml                    | yq ".entries.\"argo-cd\" | $f")"
echo "argo-workflows:        $(curl -sL https://argoproj.github.io/argo-helm/index.yaml                    | yq ".entries.\"argo-workflows\" | $f")"
echo "prometheus:            $(curl -sL https://prometheus-community.github.io/helm-charts/index.yaml      | yq ".entries.prometheus | $f")"
echo "grafana:               $(curl -sL https://grafana.github.io/helm-charts/index.yaml                   | yq ".entries.grafana | $f")"
echo "otel-collector:        $(curl -sL https://open-telemetry.github.io/opentelemetry-helm-charts/index.yaml | yq ".entries.\"opentelemetry-collector\" | $f")"
echo "vault:                 $(curl -sL https://helm.releases.hashicorp.com/index.yaml                     | yq ".entries.vault | $f")"
echo "cert-manager:          $(curl -sL https://charts.jetstack.io/index.yaml                              | yq ".entries.\"cert-manager\" | $f")"
echo "kubernetes-replicator: $(curl -sL https://helm.mittwald.de/index.yaml                                | yq ".entries.\"kubernetes-replicator\" | $f")"
echo "metrics-server:        $(curl -sL https://kubernetes-sigs.github.io/metrics-server/index.yaml        | yq ".entries.\"metrics-server\" | $f")"
echo "kiali-operator:        $(curl -sL https://kiali.org/helm-charts/index.yaml                           | yq ".entries.\"kiali-operator\" | $f")"
```

Note: the Helm **chart** version differs from the upstream app version (e.g.
the cert-manager chart is `vX.Y.Z`, Vault chart `0.32.x` vs Vault app `2.x`).
Always compare against the chart `index.yaml`, not the project's GitHub release.

### Block 3 — kubectl and Go

```bash
echo "kubectl: $(curl -sL https://dl.k8s.io/release/stable.txt)"   # use dl.k8s.io, NOT cdn.dl.k8s.io
echo "go: $(curl -sL 'https://go.dev/dl/?mode=json' | yq -p json '.[0].version')"
```

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

### For `Tiltfile` (Istio only):
When `ISTIO_CHART_VERSION` is bumped, update the two version variables
near the top of `Tiltfile`:

```starlark
version_dash = '1-30-0'   # dashed form, used in revision labels
version_dot  = '1.30.0'   # dotted form, must match ISTIO_CHART_VERSION
```

Both must stay in lockstep with the Istio chart version.

In addition, the `Tiltfile` embeds a full `kind: Deployment` manifest for
`istiod` that mirrors the Deployment rendered by the upstream Istio Helm
chart. New Istio versions frequently tweak this Deployment (new env vars,
changed args, new volume mounts, updated probes, etc.), so the embedded
manifest **may also need to be updated** to stay in sync.

The diff cannot be computed reliably from the chart alone — the user
verifies it through **ArgoCD** (which renders the chart in-cluster and
shows the diff between what ArgoCD wants to apply and what Tilt has
mutated). After the new chart is deployed:

1. Open the istiod Application in ArgoCD and inspect the diff for the
   `istiod-<version_dash>` Deployment.
2. Port any non-Tilt-specific changes (new env vars, args, volumes, etc.)
   into the embedded YAML in `Tiltfile`. Do **not** touch the bits Tilt
   injects (the `image:` reference, restart annotations, sync mounts).
3. Ask the user before making these edits if the diff is ambiguous —
   never guess at chart changes without seeing the ArgoCD diff.

## Istio Image & Binary Rebuild (required on every Istio bump)

When `ISTIO_CHART_VERSION` is bumped, the Istio fork in `/workspaces/istio`
must be synced and the images + binaries rebuilt so that the Tiltfile
live-reload loop can consume them.

1. **Sync the fork with upstream and check out the target tag**:

   ```bash
   cd /workspaces/istio
   git fetch upstream --tags
   git checkout <ISTIO_CHART_VERSION>   # e.g. 1.30.0
   ```

   The `1.x.y` release tags live on `upstream` (`istio/istio`), not on the
   `h0tbird/forked-istio` `origin`, so `git fetch --tags` alone (which only
   pulls from `origin`) is not enough — always fetch from `upstream`
   explicitly.

2. **Publish new multi-arch images to ghcr.io** so the Tiltfile can pull them
   (run from `/workspaces/meshlab`, where the `Makefile` lives):

   ```bash
   make istio-images ISTIO_HUB=ghcr.io/h0tbird ISTIO_TAG=<ISTIO_CHART_VERSION>
   ```

3. **Rebuild the Istio binaries** so the Tiltfile live-reload loop redeploys
   `pilot-discovery` with the new code (also from `/workspaces/meshlab`):

   ```bash
   make istio-binaries
   ```

## Important Considerations

- **Prefer stable releases** over pre-release/alpha/beta/RC versions for all components
- **Stay on current stable series**: When the latest version of a component is a pre-release (RC/alpha/beta), stay on the current stable major.minor series and check for the latest patch version in that series (e.g., if latest Istio is 1.31.0-rc.1, check for the latest 1.30.x stable release)
- **`gh release list` shows pre-releases inline** — the `Latest` label marks the
  newest stable release; do not blindly take the first row. As of 2026-04,
  Istio (`1.30.0-beta.0`) had a pre-release newer than the latest stable.
- **Note major version upgrades** that may introduce breaking changes
- **Dependencies**: Some components have compatibility requirements (e.g., Kiali version should be compatible with Istio version)

## Creating the PR

When the user requests a PR:

1. Create a branch off `master`, e.g. `upgrade-components-YYYY-MM`. If a branch
   with that name already exists (from a previous merged upgrade), fall back to
   a dated form like `upgrade-components-YYYY-MM-DD` rather than reusing it.
2. Commit the changes with a structured body listing each bumped component
   (`old -> new`), grouped by file.
3. Push the branch.
4. Open the PR with `gh pr create` (add `--draft` if the user asked for a draft).
   **The `istio/istio` repo is added as a
   workspace remote, so `gh` may pick it as the default upstream and fail with
   `No commits between istio:master and h0tbird:<branch>`. Always pass
   `--repo h0tbird/meshlab --base master --head <branch>` explicitly.**
   Also set `GH_PAGER=cat NO_COLOR=1` so the command does not open the pager.

   ```bash
   env GH_PAGER=cat NO_COLOR=1 gh pr create --draft \
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
| Istio | 1.30.0 | 1.30.1 | ✅ Upgraded |

### CLI Tools (.devcontainer/Dockerfile)
| Tool | Previous | Latest | Status |
|------|----------|--------|--------|
| kind | v0.31.0 | v0.32.0 | ✅ Upgraded |

Include notes about breaking changes or skipped components.
