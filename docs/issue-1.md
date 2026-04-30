# Issue 1: Cross-cluster sidecar/ambient connectivity in a multi-network mesh

## TL;DR — current status

| Direction | Cross-cluster status |
|---|---|
| ambient ↔ ambient | ✅ Works (HBONE EW gateway, port 15008) |
| sidecar ↔ sidecar | ✅ Works (SNI/AUTO_PASSTHROUGH EW gateway, port 15443) |
| ambient → remote sidecar | ❌ Not supported in Istio 1.29.x **or** 1.30.0-beta.0 — upstream [#57877](https://github.com/istio/istio/issues/57877) |
| sidecar → remote ambient | ❌ Not supported in Istio 1.29.x **or** 1.30.0-beta.0 — upstream [#57878](https://github.com/istio/istio/issues/57878) |

Same-cluster paths (any combination of sidecar/ambient) all work. The two ❌ rows are
**known upstream limitations**, not a misconfiguration of this lab.

## Lab topology recap

- Two primary clusters in a multi-network mesh:
  - `kind-pasta-1` — network `pasta-1`, pod CIDR `10.51.0.0/16`
  - `kind-pasta-2` — network `pasta-2`, pod CIDR `10.52.0.0/16`
- Mesh ID `pasta`, trust domain `pasta.local`, Istio revision `stable` (1.29.2).
- k-swarm `peer` workloads deployed in four namespaces per cluster:
  - `swarm-ambient-n1`, `swarm-ambient-n2` (ambient/ztunnel + waypoint)
  - `swarm-sidecar-n1`, `swarm-sidecar-n2` (sidecar injection)
- Each peer pod periodically polls `informer.swarm-informer/services` and HTTP-GETs every
  peer it learns about. Logs (`/tmp/hops/all.log` after running the collection one-liner
  below) carry `src` / `dst` / `http.status` for every hop.

## What was done to get to this state

1. **Renamed** the original ambient EW gateway from `istio-eastwestgateway` to
   `istio-eastwestgateway-ambient`
   ([charts/ewgw/templates/gateway-ambient.yaml](../charts/ewgw/templates/gateway-ambient.yaml)).
   It still uses `gatewayClassName: istio-east-west`, listener `HBONE/15008`,
   `tls.mode: Terminate`, `gateway.istio.io/tls-terminate-mode: ISTIO_MUTUAL`.
2. **Added** a sibling sidecar EW gateway `istio-eastwestgateway-sidecar`
   ([charts/ewgw/templates/gateway-sidecar.yaml](../charts/ewgw/templates/gateway-sidecar.yaml)).
   - `gatewayClassName: istio` (NOT `istio-east-west` — that class only accepts the
     ambient HBONE listener).
   - Single listener: `port: 15443`, `protocol: TLS`, `hostname: "*.local"`,
     `tls.mode: Passthrough`.
   - `topology.istio.io/network` label on the Gateway → istiod auto-registers the
     resulting Service as the cross-network gateway for the local network and turns on
     **AUTO_PASSTHROUGH** SNI routing for sidecars.
3. **Enabled `PILOT_ENABLE_ALPHA_GATEWAY_API=true`** on istiod
   ([charts/istio/templates/applicationsets/istio-istiod.yaml](../charts/istio/templates/applicationsets/istio-istiod.yaml)).
   The `protocol: TLS` listener on a Gateway-API `Gateway` is alpha in 1.29.x and is
   silently ignored without this flag (the gateway provisions but its Deployment stays
   `Degraded` and istiod never programs an inbound 15443 listener).
4. **Updated swarmctl** ([h0tbird/k-swarm PR #140](https://github.com/h0tbird/k-swarm/pull/140))
   so `--multi-cluster --dataplane-mode sidecar` adds the bits needed for cross-cluster
   sidecar discovery:
   - The sidecar `peer` Service gets the `istio.io/global: "true"` label (required by the
     mesh's `serviceScopeConfigs` filter; istiod won't publish the service to remote
     clusters without it).
   - The matching `DestinationRule` sets
     `localityLbSetting.enabled: false` with
     `failoverPriority: [topology.istio.io/cluster]` so cross-cluster failover is actually
     exercised instead of always landing on the local pod.
5. **Wired the swarmctl `--multi-cluster` flag into the lab bootstrap**
   ([bin/meshlab](../bin/meshlab), `deploy-workloads` section) so re-creating the lab
   produces the right config out of the box.

## Current connectivity matrix (after all the changes above)

Legend: ✅ observed cross-cluster traffic; ❌ rooted in an upstream architectural
limitation (calls succeed against the local-cluster endpoint but the remote endpoint is
filtered out of EDS).

| Source ↓ \ Destination → | p1/amb-n1 | p1/amb-n2 | p1/sc-n1 | p1/sc-n2 | p2/amb-n1 | p2/amb-n2 | p2/sc-n1 | p2/sc-n2 |
|---|---|---|---|---|---|---|---|---|
| **p1 / ambient-n1** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| **p1 / ambient-n2** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| **p1 / sidecar-n1** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ |
| **p1 / sidecar-n2** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ |
| **p2 / ambient-n1** | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ |
| **p2 / ambient-n2** | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ |
| **p2 / sidecar-n1** | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **p2 / sidecar-n2** | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

## Why the two ❌ patterns can't be fixed (in 1.29.x or 1.30.0-beta.0)

Verified by reading the source at tags `1.29.2` and `1.30.0-beta.0` (both fetched into
`/workspaces/istio`).

`pilot/pkg/xds/endpoints/ep_filters.go` `selectNetworkGateways(...)` is **identical**
between the two versions:

```go
// If we operate in ambient multi-network mode skip gateways that don't have HBONE port
if features.EnableAmbientMultiNetwork && !isSidecarProxy(b.proxy) {
    // ambient (ztunnel/waypoint) only consider gateways with HBONEPort != 0
}
// Sidecar proxies cannot talk to ambient E/W gateway for now, so when we see an ambient
// E/W gateway (e.g., a gateway that listens on hbone port, but does not have an mTLS port
// we filter it out.
if isSidecarProxy(b.proxy) {
    // sidecar Envoys only consider gateways with Port != 0 (the 15443 mTLS one)
}
```

Plus a few lines earlier:

```go
// Cross-network traffic relies on mTLS for SNI routing in sidecar mode.
if (!features.EnableAmbientMultiNetwork || isSidecarProxy(b.proxy)) && !isMtlsEnabled(lbEp) {
    continue
}
```

Translated to our ❌ cases:

- **sidecar src → remote ambient dst.** Sidecar Envoy is only ever pointed at the
  15443/PASSTHROUGH EW gateway; that gateway expects the destination pod to terminate
  Istio mTLS on the app port. Ambient pods don't — ztunnel only listens on HBONE/15008.
  Even if we tricked the sidecar into talking to the HBONE gateway, sidecar Envoy
  cannot speak HBONE outbound at all.
- **ambient src → remote sidecar dst.** Ztunnel sends HBONE/double-HBONE to the ambient
  EW gateway, which forwards HBONE to the destination's ztunnel. Sidecar pods have no
  ztunnel and no HBONE listener. The ambient EW gateway has no logic to "downgrade"
  HBONE to plain mTLS toward a sidecar pod.

The 1.30 EW TLS-passthrough feature (`releasenotes/notes/ewgw-tls-passthrough.yaml`)
**does not bridge these modes** — it adds operator-authored TLSRoute passthrough on the
**ambient** EW gateway (motivating example: exposing the K8s API server cross-network),
not automatic per-Service SNI plumbing the way the sidecar 15443 gateway does. So it
cannot replace either of the two EW gateways we deploy today.

## Upstream tracking

| # | Title | What it covers |
|---|---|---|
| [istio#57878](https://github.com/istio/istio/issues/57878) | "Sidecar sees Ambient E/W Gateway, can't communicate" | Our `sidecar → remote ambient` ❌. Maintainer @krinkinmu confirms it's deferred until pure-ambient multi-network stabilizes. PR [#58131](https://github.com/istio/istio/pull/58131) is a partial fix (filter ambient EW gateways out of sidecar EDS) — not a real bridge. |
| [istio#57877](https://github.com/istio/istio/issues/57877) | "Sidecar global services cause tcp reset" | Our `ambient → remote sidecar` ❌ when the sidecar Service is labeled `istio.io/global=true`. |
| [istio#54921](https://github.com/istio/istio/issues/54921) | "Sidecars cannot send HBONE to headless services handled by ztunnel" | Same root cause, single-cluster variant. @howardjohn has a prototype patch (unmerged) extending `BestEffortInferServiceMTLSMode` with an `HBONE` option. |
| [istio#51445](https://github.com/istio/istio/issues/51445) | "Tracking issue for sidecar -> waypoint interop" | Umbrella tracking for sidecar↔ambient migration interop. |
| [istio#42137](https://github.com/istio/istio/issues/42137) | "Support Single Network Multicluster for Ambient" | Adjacent ambient multi-cluster evolution. |

## Possible (operator-authored) workarounds — not implemented

- **Put a waypoint in front of the sidecar Service** in the destination cluster. Then
  ambient sources can reach the sidecar workload via HBONE → ambient EW gateway →
  waypoint, and the waypoint re-originates plain mTLS to the sidecar pod. This unlocks
  the `ambient src → remote sidecar dst` direction only. (See
  `EnableAmbientWaypointMultiNetwork`, on by default in 1.29.x.)
- **No symmetric workaround** exists for `sidecar src → remote ambient dst`. The only
  real options are (a) move the source workload to ambient, or (b) wait for a future
  upstream feature that lets sidecars egress through the ambient HBONE EW gateway.

## Useful commands

```sh
# Refresh peer hop logs
mkdir -p /tmp/hops
for ctx in kind-pasta-1 kind-pasta-2; do
  for ns in swarm-ambient-n1 swarm-ambient-n2 swarm-sidecar-n1 swarm-sidecar-n2; do
    pod=$(kubectl --context $ctx -n $ns get pod -l app=peer -o name | head -1)
    [ -z "$pod" ] && continue
    echo "=== $ctx/$ns/$pod ==="
    kubectl --context $ctx -n $ns logs $pod -c peer --tail=300 2>/dev/null \
      || kubectl --context $ctx -n $ns logs $pod --tail=300
  done
done > /tmp/hops/all.log 2>&1

# Aggregate into a (src cluster|ns) -> (dst cluster|ns) = http.status table
grep -oE '"src": \{"cluster":"[^"]+","node":"[^"]+","namespace":"[^"]+"[^}]*\}, "dst": \{"cluster":"[^"]+","node":"[^"]+","namespace":"[^"]+"[^}]*\}, "http": \{"status":[0-9]+' /tmp/hops/all.log \
  | sed -E 's/.*"src": \{"cluster":"([^"]+)".*"namespace":"([^"]+)".*"dst": \{"cluster":"([^"]+)".*"namespace":"([^"]+)".*"status":([0-9]+).*/\1|\2 -> \3|\4 = \5/' \
  | sort | uniq -c

# Verify the swarmctl multi-cluster bits made it onto the sidecar peer Services / DRs
for ctx in kind-pasta-1 kind-pasta-2; do
  for ns in swarm-sidecar-n1 swarm-sidecar-n2; do
    echo "=== $ctx/$ns ==="
    kubectl --context $ctx -n $ns get svc peer -o jsonpath='{.metadata.labels}'; echo
    kubectl --context $ctx -n $ns get destinationrule -o yaml | grep -A4 localityLbSetting
  done
done

# Check that the two EW gateways exist and are Healthy
for ctx in kind-pasta-1 kind-pasta-2; do
  kubectl --context $ctx -n istio-system get gateway,svc | \
    grep -E 'istio-eastwestgateway-(ambient|sidecar)'
done

# Look for the multi-network EDS warning in istiod logs (should be quiet for sidecar
# services now; will still appear for ambient->sidecar / sidecar->ambient remote pairs)
kubectl --context kind-pasta-1 -n istio-system logs deploy/istiod-stable \
  | grep -i 'different network\|no reachable E/W gateway'
```

## History (what changed since the original write-up)

The original version of this document described the regression introduced by commit
`bf10f6e03c` ("Ambient multi-cluster multi-network multi-primary (#28)"), which replaced
the upstream classic `istio/gateway` (15443/AUTO_PASSTHROUGH) with an ambient-only HBONE
gateway. Steps that were taken since then (in chronological order):

1. Built a connectivity matrix from `/tmp/hops/all.log`. Initial state: only ambient↔ambient
   cross-cluster worked; everything else was local-only.
2. Renamed the original gateway to `istio-eastwestgateway-ambient` and added a sibling
   `istio-eastwestgateway-sidecar`. First attempt used `gatewayClassName: istio-east-west`
   which silently rejected the TLS listener — fixed by switching to `gatewayClassName: istio`.
3. Hit a `Degraded` Deployment on the new sidecar gateway. Root cause: the `protocol: TLS`
   listener is alpha in 1.29.x. Fixed by enabling `PILOT_ENABLE_ALPHA_GATEWAY_API=true`
   on istiod. Both gateways then went `Healthy`.
4. Updated swarmctl ([PR #140](https://github.com/h0tbird/k-swarm/pull/140)) to add
   `--multi-cluster` for the sidecar dataplane mode → labels Service with
   `istio.io/global=true` and configures `localityLbSetting` for cross-cluster failover.
   Re-deployed peers.
5. Re-ran the matrix. **NEW:** sidecar↔sidecar cross-cluster works. Remaining ❌ are the
   two cross-mode cross-cluster cells.
6. Inspected Istio 1.29.2 source then diffed against 1.30.0-beta.0 (370 commits, 63
   release notes). Confirmed `selectNetworkGateways` is unchanged and the cross-mode gap
   is still architectural in 1.30.0-beta.0.
7. Searched open Istio issues. Found upstream issues
   [#57877](https://github.com/istio/istio/issues/57877) and
   [#57878](https://github.com/istio/istio/issues/57878) tracking exactly these two
   cells. Both labeled `feature/Multi-cluster` + `area/ambient`, both deferred.

## References

- [charts/ewgw/templates/gateway-ambient.yaml](../charts/ewgw/templates/gateway-ambient.yaml)
- [charts/ewgw/templates/gateway-sidecar.yaml](../charts/ewgw/templates/gateway-sidecar.yaml)
- [charts/istio/templates/applicationsets/istio-istiod.yaml](../charts/istio/templates/applicationsets/istio-istiod.yaml)
- [bin/meshlab](../bin/meshlab) — `deploy-workloads` section
- Upstream code paths verified: `pilot/pkg/xds/endpoints/ep_filters.go`,
  `pilot/pkg/networking/core/cluster.go`, `pilot/pkg/serviceregistry/kube/conversion.go`,
  `pilot/pkg/features/ambient.go`.
- k-swarm PR with the multi-cluster bits: <https://github.com/h0tbird/k-swarm/pull/140>.
