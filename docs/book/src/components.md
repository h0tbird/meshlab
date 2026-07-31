# Components

`meshlab create` is a dependency graph of idempotent **sections** defined in
`bin/meshlab` (`meshlab list` prints them). The graph itself lives in the `DEPS`
associative array in `lib/common.sh` and is executed with `make -j`, so
independent sections run in parallel.

| Section | What it does |
| ------- | ------------ |
| `cloud-provider-kind` | Creates the Docker `kind` network and starts the `kindccm` containers that hand out `LoadBalancer` IPs. |
| `pull-through-cache` | Starts the [zot](./components/pull-through.md) registry used as an on-demand pull-through cache. |
| `create-clusters` | Creates the [kind](./components/kind.md) clusters with per-cluster pod/service CIDRs and a `<cell>.local` DNS domain. |
| `add-registries-to-containerd` | Points each cluster's containerd at zot. |
| `setup-kubeconfig` | Rebuilds the in-container kubeconfig with only the `kind-*` contexts, plus an in-cluster variant. |
| `setup-flat-network` | Adds the static routes that make each cell a [flat L3 network](./components/flat-network.md). |
| `install-gateway-api` | Applies the Gateway API CRDs, pinned to the bundle the pinned Istio version supports. |
| `install-k8s-gateway` | Installs `k8s_gateway` so `demo.lab` names resolve to `LoadBalancer` IPs. |
| `setup-coredns` | Rewrites the [CoreDNS](./components/coredns.md) Corefile for the `<cell>.local` zone and forwards `demo.lab`. |
| `setup-argocd` | Installs [Argo CD](./components/argocd.md) on the manager cluster. |
| `register-argocd-clusters` | Registers every cluster in Argo CD with `name` and `cell` labels used by the `ApplicationSet` generators. |
| `install-applicationsets` | Renders `charts/*` and applies the `ApplicationSet`s and `WorkflowTemplate`s. |
| `setup-argowf` | Installs [Argo Workflows](./components/argo-workflows.md) on the manager cluster. |
| `kiali-secrets` | Creates the Kiali remote-cluster secrets. |
| `bootstrap-dag` | Submits the Workflow that syncs every `ApplicationSet` in dependency order. |
| `istio-endpoint-discovery` | Exchanges `istioctl create-remote-secret` credentials between the clusters of a cell. |
| `grafana-git-sync` | Optional; wires Grafana to the dashboards in the repo (needs `GITHUB_TOKEN`). |
| `tilt-up` | Starts one [Tilt](./development.md) instance per workload cluster. |
| `deploy-workloads` | Deploys the [k-swarm workloads](./components/workloads.md). |
| `publish-ports` | `socat` forwards the `LoadBalancer` services to `127.0.0.1`. |

## Pinned versions

All component versions are `readonly` constants at the top of `bin/meshlab`,
each with a link to where the latest version can be checked. The
`upgrade-components` skill (`.github/skills/upgrade-components/`) automates
bumping them.
