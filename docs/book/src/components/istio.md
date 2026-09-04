# Istio

Istio is the reason this lab exists. Every workload cluster runs its own
control plane (**multi-primary**), and the clusters of a cell federate with each
other through remote secrets.

## What is installed

All from the official charts at
`https://blob.istio.io/istio-release/charts`, pinned by
`ISTIO_CHART_VERSION` in `bin/meshlab`:

| Argo CD app | Chart | Notes |
| ----------- | ----- | ----- |
| `istio-base` | `base` | CRDs and cluster roles. |
| `istio-cni` | `cni` | Required by ambient. |
| `istio-istiod` | `istiod` | `profile: ambient` when `MODE=ambient`, revisioned. |
| `istio-ztunnel` | `ztunnel` | The ambient L4 node proxy, **`MODE=ambient` only**. |
| `istio-nsgw` | `gateway` | North-south (ingress) gateway, with a custom bootstrap from `conf/istio`. |
| `istio-ewgw` | `charts/ewgw` (local) | East-west gateways, **`--network-mode multi` only**. The sidecar gateway (TLS 15443) is always deployed; the ambient one (HBONE 15008) only with `MODE=ambient`. |
| `istio-issuers` | `charts/issuers` (local) | See [cert-manager](./cert-manager.md). |

istiod is deployed with the revision derived from the version (dots replaced by
dashes, e.g. `1-31-0-alpha-2`) and the revision tags `stable`, `canary` and
`default`. Workloads therefore opt in with `istio.io/rev: stable` rather than a
raw revision.

## Per-cell / per-cluster settings

The `ApplicationSet` generator injects `{{name}}` (cluster) and
`{{metadata.labels.cell}}` (cell) into the istiod values:

| Setting | Value |
| ------- | ----- |
| `global.multiCluster.clusterName` | cluster name |
| `meshConfig.trustDomain` | `<cell>.local` |
| `global.proxy.clusterDomain` | `<cell>.local` (matches the kubeadm DNS domain) |
| `global.meshID` | cell name |
| `global.network` | cluster name in `multi` mode, cell name in `single` mode |

A few notable `pilot.env` settings:

- `AMBIENT_ENABLE_MULTI_NETWORK: "true"` — despite the name, this is the master
  switch for ambient **cross-cluster** endpoint discovery, so it is on in both
  network modes. See `docs/single-network-mode.md`.
- `ENABLE_NATIVE_SIDECARS: "true"` — inject the sidecar as a Kubernetes native
  sidecar (sidecar mode only).
- `PILOT_ENABLE_ALPHA_GATEWAY_API: "true"` — needed for the `TLS`/PASSTHROUGH
  listener of the sidecar east-west gateway.
- `AUTO_RELOAD_PLUGIN_CERTS: true` — pick up `cacerts` renewals without a
  restart.

## Gateways

`charts/ewgw` renders two Gateway API objects per cluster, both labelled with
`topology.istio.io/network`:

- **ambient**: port `15008`, `HBONE` protocol, TLS `Terminate` with
  `ISTIO_MUTUAL`.
- **sidecar**: port `15443`, `TLS` protocol, `Passthrough` mode (SNI
  auto-passthrough).

In `--network-mode single` neither is deployed: the cell is a flat L3 network,
so proxies dial remote pod IPs directly.

## Everyday commands

List the remote clusters each `istiod` is connected to:
```console
istioctl --context kind-pasta-1 remote-clusters
```

Re-exchange the remote secrets if federation breaks:
```console
meshlab run istio-endpoint-discovery
```

Check what a proxy or ztunnel actually sees:
```console
istioctl --context kind-pasta-1 proxy-status
istioctl --context kind-pasta-1 ztunnel-config workload
istioctl --context kind-pasta-1 ztunnel-config service
```

Analyse the config of a namespace:
```console
istioctl --context kind-pasta-1 analyze -n swarm-sidecar-n1
```

Access the `istiod` ControlZ UI (note the revisioned deployment name):
```console
istioctl --context kind-pasta-1 dashboard controlz deployment/istiod-1-31-0-alpha-2.istio-system
```
