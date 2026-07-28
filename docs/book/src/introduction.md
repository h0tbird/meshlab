# Introduction

Welcome to the MeshLab repository! In this lab, you will find a setup to
validate Istio configurations in a cell-based architecture. A **cell** is an
architecture block representing a unit of isolation and scalability. The lab
defines two workload cells, named `pasta` and `pizza`, each composed of two
clusters, plus a **manager** cluster (`mnger-1`) that hosts the control tooling.
Every workload cluster runs its own Istio control plane (multi-primary).

By default only the `pasta` cell is created; pass `--cell-count 2` to also
create `pizza`.

| Cell    | Clusters            | Trust domain  | Pod CIDRs                     |
| ------- | ------------------- | ------------- | ----------------------------- |
| `mngr`  | `mnger-1`           | n/a           | `10.41.0.0/16`                |
| `pasta` | `pasta-1` `pasta-2` | `pasta.local` | `10.51.0.0/16` `10.52.0.0/16` |
| `pizza` | `pizza-1` `pizza-2` | `pizza.local` | `10.61.0.0/16` `10.62.0.0/16` |

Although the cells share the same root CA for their cryptographic material,
each one uses a different SPIFFE trust domain and each cluster within a cell
gets its own intermediate CA. The kind clusters are also created with the
kubeadm DNS domain set to `<cell>.local`, so in-cluster FQDNs look like
`peer.swarm-ambient-n1.svc.pasta.local` instead of the usual `cluster.local`.

Clusters run on [kind](./components/kind.md), all attached to the same Docker
`kind` network. Every cluster gets non-overlapping pod and service CIDRs and
`setup-flat-network` installs static routes between the sibling clusters of a
cell, so a cell is a [flat L3 network](./components/flat-network.md). On top of
that, the Istio network topology is selectable:

- `--network-mode multi` (default): one Istio network **per cluster**, so
  cross-cluster mTLS traffic is routed through the east-west gateways.
- `--network-mode single`: one Istio network **per cell**, so Envoy and ztunnel
  dial remote pod IPs directly and the east-west gateways are not deployed.

## What deploys what

Helm, driven directly by `bin/meshlab`, installs the bootstrap layer:

- [Argo CD](https://artifacthub.io/packages/helm/argo-cd-oci/argo-cd) (manager
  cluster)
- [Argo Workflows](https://artifacthub.io/packages/helm/argo/argo-workflows)
  (manager cluster)
- [k8s_gateway](https://github.com/k8s-gateway/k8s_gateway) (every cluster, for
  `demo.lab` resolution)

Everything else is described as Argo CD `ApplicationSet`s (rendered from
`charts/*/templates/applicationsets/`) and synced in dependency order by a
single Argo Workflows DAG:

- [Vault](https://artifacthub.io/packages/helm/hashicorp/vault)
- [cert-manager](https://artifacthub.io/packages/helm/cert-manager/cert-manager)
- [kubernetes-replicator](https://artifacthub.io/packages/helm/kubernetes-replicator/kubernetes-replicator)
- [metrics-server](https://artifacthub.io/packages/helm/metrics-server/metrics-server)
- [Prometheus](https://artifacthub.io/packages/helm/prometheus-community/prometheus)
- [Grafana](https://artifacthub.io/packages/helm/grafana/grafana)
- [OpenTelemetry Collector](https://artifacthub.io/packages/helm/opentelemetry-helm/opentelemetry-collector)
- [Kiali](https://artifacthub.io/packages/helm/kiali/kiali-operator)
- [Istio](https://artifacthub.io/packages/helm/istio-official/base): `base`,
  `cni`, `istiod`, `ztunnel`, the north-south gateway, and — in `multi` network
  mode — the east-west gateways

Finally, [k-swarm](https://github.com/h0tbird/k-swarm) workloads are deployed
into `swarm-ambient-*` and `swarm-sidecar-*` namespaces so there is real mesh
traffic to observe.

The purpose of this lab is to test and validate different Istio configurations
in a realistic environment.
