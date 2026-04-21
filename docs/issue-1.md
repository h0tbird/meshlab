# Issue 1: Cross-cluster sidecar traffic broken after switching to ambient east-west gateway

## Symptom

Cross-cluster traffic between sidecar-injected workloads stopped working after enabling
ambient mode in both clusters. Specifically, `worker` in `service-1` (kind-pasta-1) can no
longer reach `worker` in `service-2` (kind-pasta-2) (and vice versa). Local in-cluster traffic
still works fine.

## Environment

- Two primary clusters in a multi-network mesh:
  - `kind-pasta-1` — network `pasta-1`, pod CIDR `10.51.0.0/16`, EW gateway LB `172.18.0.20`
  - `kind-pasta-2` — network `pasta-2`, pod CIDR `10.52.0.0/16`, EW gateway LB `172.18.0.21`
- Mesh ID: `pasta`, trust domain: `pasta.local`.
- Istio revision: `1-29-2`.
- `istio-remote-secret-pasta-1` / `istio-remote-secret-pasta-2` exist and are accepted by
  istiod (informers from `cluster[pasta-2]` for Pods/Services/EndpointSlices/Waypoints sync
  successfully).
- Ambient is enabled (ztunnel + istio-cni running), but the `service-1` / `service-2`
  namespaces still use **classic sidecar injection** (`istio.io/rev=stable`, pods have the
  `istio-proxy` container).

## Diagnosis

### 1. EDS only contains the local endpoint

```
$ istioctl --context kind-pasta-1 -n service-1 proxy-config endpoints deploy/worker \
    --cluster 'outbound|80||worker.service-2.svc.cluster.local'

ENDPOINT             STATUS      OUTLIER CHECK     CLUSTER
10.51.0.115:8082     HEALTHY     OK                outbound|80||worker.service-2.svc.cluster.local
```

Only the **local** pasta-1 endpoint is present. The pasta-2 endpoint is missing entirely,
even though istiod is connected to pasta-2 and has its services in cache.

### 2. istiod explicitly says it has no E/W gateway for the remote network

```
{"level":"warn","scope":"ads",
 "msg":"Workload waypoint belongs to a different network (pasta-2), but no E/W gateway configured, skipping it."}
{"level":"warn","scope":"ads",
 "msg":"Workload helloworld-v2 belongs to a different network (pasta-2), but no E/W gateway configured, skipping it."}
```

Repeated continuously during xDS pushes.

### 3. The east-west gateway is HBONE-only

`charts/ewgw/templates/gateway.yaml` (introduced by commit `bf10f6e03c`,
"Ambient multi-cluster multi-network multi-primary"):

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: istio-eastwestgateway
  namespace: istio-system
  labels:
    topology.istio.io/network: <network>
spec:
  gatewayClassName: istio-east-west
  listeners:
  - name: mesh
    port: 15008
    protocol: HBONE
    tls:
      mode: Terminate
      options:
        gateway.istio.io/tls-terminate-mode: ISTIO_MUTUAL
```

Resulting Service:

```
$ kubectl -n istio-system get svc istio-eastwestgateway -o wide
NAME                    TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)
istio-eastwestgateway   LoadBalancer   10.96.80.237   172.18.0.20   15021:31535/TCP,15008:32712/TCP
```

There is **no** `15443 / TLS / AUTO_PASSTHROUGH` listener — the listener that classic sidecars
need for cross-network traffic.

The previous chart (replaced in `bf10f6e03c`) was the upstream `istio/gateway` chart with
ports `15443 / 15012 / 15017 / 15021`, which is why cross-cluster traffic used to work.

### 4. Why istiod silently drops the remote endpoint

This is a known limitation in 1.29. From
`istio/tests/integration/ambient/baseline_test.go`:

> Currently sidecars cannot talk to ambient endpoints on a remote network.
>
> Sidecars can't use double-HBONE and therefore cannot use ambient E/W gateways. And if we
> filter out all the ambient gateways, due to an old bug/feature, EDS generation code, when
> it can't find any E/W gateways for an endpoint, it just assumes that it's directly
> reachable and does not even try to use HBONE — this is not correct.
>
> See https://github.com/istio/istio/issues/57878

So istiod:

1. Sees the remote workload `worker.service-2` in `pasta-2`.
2. Looks for a non-HBONE network gateway for `pasta-2` to put into the sidecar's EDS.
3. Finds only an HBONE gateway, which sidecars can't use.
4. Drops the endpoint from the sidecar's EDS and emits the
   `"... belongs to a different network ..., but no E/W gateway configured, skipping it."`
   warning.

That leaves only the local pasta-1 endpoint, matching what we observed.

## Root cause

Commit `bf10f6e03c` swapped the classic SNI east-west gateway (port 15443
AUTO_PASSTHROUGH) for an ambient HBONE-only Gateway-API gateway (port 15008). The new
gateway is correct for ambient/ztunnel traffic but incompatible with classic sidecars,
which still inject in `service-1` and `service-2`. As a result, all cross-cluster
sidecar-to-sidecar traffic loses its remote endpoints.

## Fix options

### A. Re-add a classic SNI east-west gateway alongside the HBONE one (recommended)

Deploy the upstream `istio/gateway` Helm chart (or an equivalent
`Deployment` + `Service` + `networking.istio.io/v1 Gateway`) in `istio-system` with:

- Service ports: `15021` (status), `15443` (TLS pass-through), `15012` (XDS), `15017` (webhook).
- A `networking.istio.io/v1 Gateway` with a `*.local` host on port 15443,
  `tls.mode: AUTO_PASSTHROUGH`.
- Service label `topology.istio.io/network=<network>` so istiod discovers it as the
  network gateway for that network.

Keep the existing HBONE gateway for ambient. Once istiod sees a non-HBONE network gateway
for `pasta-2`, the remote endpoint will reappear in the sidecar's EDS as
`<gateway_ip>:15443` with SNI routing, and traffic will work again.

The change should be made in `charts/ewgw` (or a new sibling chart, e.g.
`charts/ewgw-sni`) and exposed via a new ApplicationSet next to
`charts/istio/templates/applicationsets/istio-ewgw.yaml`. Do **not** patch the cluster
directly — Argo CD will revert it.

Implementation note: when validated locally, the new SNI gateway showed up correctly in
istiod's `/debug/networkz` (both `pasta-1` and `pasta-2` 15443 entries appeared), but the
sidecar's EDS for `worker.service-2.svc.cluster.local` still only contained the local
endpoint. Possible follow-ups if this persists after deploying via Argo CD:

- Add a `DestinationRule` for the cross-cluster service with
  `trafficPolicy.tls.mode: ISTIO_MUTUAL` (or rely on a `STRICT` `PeerAuthentication`)
  so `isMtlsEnabled(lbEp)` returns true in `EndpointsByNetworkFilter`.
- Confirm `b.gateways().IsMultiNetworkEnabled()` is true from the sidecar's perspective
  (an istiod restart helps after the new gateway lands).
- Double-check that the SNI gateway Service ends up with cluster ID = its own kind
  cluster (it should, via `topology.istio.io/cluster` auto-labeling).

### B. Move workloads to ambient

Label `service-1` and `service-2` namespaces with
`istio.io/dataplane-mode=ambient` and stop injecting sidecars (remove the
`istio.io/rev=stable` label). Ambient workloads can use the existing HBONE EW gateway
through ztunnel without further changes.

## Useful commands used during investigation

```sh
# List clusters and EW gateways
for c in kind-pasta-1 kind-pasta-2; do
  kubectl --context $c -n istio-system get svc istio-eastwestgateway --show-labels
done

# Check multi-cluster secrets
for c in kind-pasta-1 kind-pasta-2; do
  kubectl --context $c -n istio-system get secrets -l istio/multiCluster=true
done

# Check EDS for the remote service from a sidecar workload
istioctl --context kind-pasta-1 -n service-1 proxy-config endpoints deploy/worker \
  --cluster 'outbound|80||worker.service-2.svc.cluster.local'

# Look for the smoking-gun warning in istiod logs
kubectl --context kind-pasta-1 -n istio-system logs deploy/istiod-1-29-2 \
  | grep -i 'different network'
```

## References

- Upstream issue: https://github.com/istio/istio/issues/57878
- Test that documents the limitation:
  `istio/tests/integration/ambient/baseline_test.go` (search for
  "Sidecars can't use double-HBONE").
- Commit that introduced the regression: `bf10f6e03c`
  "Ambient multi-cluster multi-network multi-primary (#28)".
