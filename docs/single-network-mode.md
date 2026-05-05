# `--network-mode single` particularities

This document captures the non-obvious bits of running meshlab with
`--network-mode single` (a single flat L3 network across both `pasta-*`
clusters, courtesy of Cilium ClusterMesh) instead of the default
`--network-mode multi`.

## TL;DR

- Single-network mode means **every cluster reports the same `network`
  label** to istiod. Pod IPs are directly routable across clusters
  (Cilium ClusterMesh provides the flat L3), so the East-West gateways
  are bypassed for cross-cluster traffic — Envoy/ztunnel dial pod IPs
  directly.
- Despite the flat L3, **ambient cross-cluster endpoint discovery still
  has to be explicitly enabled** with `AMBIENT_ENABLE_MULTI_NETWORK=true`
  on istiod. The flag's name is misleading: it is actually the master
  switch for ambient *cross-cluster* endpoint discovery, regardless of
  whether the clusters share a network or not.
- ztunnel applies a strong **same-cluster locality preference** that is
  not influenced by `DestinationRule.trafficPolicy.loadBalancer.localityLbSetting`.
  Cross-cluster ambient traffic therefore only flows on local-endpoint
  failure (or when steered through the destination waypoint, where the
  DR is honored).

## Chart wiring

`charts/istio/values.yaml` gates the mode:

```yaml
networkMode: single   # or "multi"
```

[charts/istio/templates/applicationsets/istio-istiod.yaml](../charts/istio/templates/applicationsets/istio-istiod.yaml)
translates that to istiod settings:

| Setting                         | `multi`                          | `single`                                   |
| ------------------------------- | -------------------------------- | ------------------------------------------ |
| `global.network`                | `'{{name}}'` (per-cluster)       | `'{{metadata.labels.cell}}'` (per-cell)    |
| `AMBIENT_ENABLE_MULTI_NETWORK`  | `"true"`                         | `"true"` (always — see below)              |
| `meshID`                        | `'{{metadata.labels.cell}}'`     | `'{{metadata.labels.cell}}'`               |

`network` collapses to the cell name in single mode, so both
`kind-pasta-1` and `kind-pasta-2` advertise `network=pasta`. Istiod
treats them as the same network, picks pod IPs directly for EDS, and
skips the EW-gateway address rewriting.

## The `AMBIENT_ENABLE_MULTI_NETWORK` gotcha

The original chart used to disable this flag in single-network mode
(reasoning: "we are not multi-network, so don't enable multi-network
discovery"). That was wrong. In Istio 1.29.x the flag controls **all
ambient cross-cluster endpoint discovery**, not just the multi-network
EW-gateway address rewriting. Symptoms when it is `false`:

- `istioctl ztunnel-config service` shows `1/1 ENDPOINTS` for an
  ambient peer service that has pods in both clusters.
- `istioctl ztunnel-config workload` shows zero remote-cluster
  workloads, even when the istio-remote-secret is present and istiod
  has discovered the remote cluster.
- Sidecar Envoy EDS for the same service shows all endpoints
  (including remote pod IPs). So the gap is purely on the ambient/ztunnel
  data path.

With the flag set to `true`:

- ztunnel sees `2/2` endpoints (one per cluster).
- Remote ambient pods *and* remote waypoints appear in
  `ztunnel-config workload`.

Because there is no scenario in this lab where we want ambient to be
deliberately limited to local-cluster endpoints, the chart now sets the
flag to `"true"` unconditionally.

## Locality preference (ambient)

Even with discovery working, `ztunnel`'s built-in locality logic
**always prefers same-cluster endpoints** when they are healthy. It
does not honor the same `DestinationRule` knobs that Envoy does, in
particular:

```yaml
trafficPolicy:
  loadBalancer:
    localityLbSetting:
      enabled: false
    failoverPriority: [topology.istio.io/cluster]
```

…has no effect on the source ztunnel. The DR *is* honored at the
destination waypoint, so if you need active cross-cluster distribution
you must steer traffic through the destination waypoint (e.g. with a
`use-waypoint` annotation that targets a non-local waypoint, or via an
explicit per-route `Route` to a `ServiceEntry`/waypoint).

To validate cross-cluster reachability without changing routing, just
scale the local backend to zero — ztunnel will failover to the remote
endpoint:

```bash
kubectl --context kind-pasta-1 -n swarm-ambient-n2 scale deploy peer --replicas=0
# probe from another ambient pod; dst.cluster will be pasta-2
```

## Sidecar behavior

Sidecars are unaffected by `AMBIENT_ENABLE_MULTI_NETWORK`. Their EDS
includes all pod IPs across clusters as soon as the remote secret is in
place, and the standard `localityLbSetting` / `failoverPriority` knobs
on the DR control distribution as documented upstream.

## Connectivity matrix (single-network)

With the chart fix in place:

| Direction                    | Status |
| ---------------------------- | ------ |
| sidecar ↔ sidecar (in-cell)  | ✅ active LB across clusters via DR |
| ambient ↔ ambient (in-cell)  | ✅ discovery works; **failover only**, no active LB |
| ambient → sidecar (in-cell)  | ✅ as same-cluster; cross-cluster on failover |
| sidecar → ambient (in-cell)  | ✅ as same-cluster; cross-cluster on failover |

Compare with [docs/issue-1.md](./issue-1.md) for the equivalent
multi-network results, where the two ambient↔sidecar cross-cluster
combinations are blocked by upstream issues
[istio/istio#57877](https://github.com/istio/istio/issues/57877) and
[istio/istio#57878](https://github.com/istio/istio/issues/57878).

## Diagnostic recipes

```bash
# How many endpoints does the source ztunnel see for an ambient service?
istioctl --context kind-pasta-1 ztunnel-config service \
  | grep swarm-ambient.*peer

# Which workloads does the source ztunnel know about? (look for remote IPs)
istioctl --context kind-pasta-1 ztunnel-config workload \
  | grep -E 'NAMESPACE|swarm-ambient'

# Compare with what a sidecar Envoy sees (rich EDS):
sc=$(kubectl --context kind-pasta-1 -n swarm-sidecar-n1 \
       get pod -l app=peer -o name | head -1)
istioctl --context kind-pasta-1 proxy-config endpoints \
  -n swarm-sidecar-n1 $sc | grep peer.swarm-sidecar
```
