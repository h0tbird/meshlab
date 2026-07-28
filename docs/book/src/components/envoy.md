# Envoy

Envoy is the proxy behind Istio's sidecars and gateways. In this lab you will
find it in three shapes: as a sidecar in the `swarm-sidecar-*` namespaces, as
the north-south gateway (`istio-nsgw`) and, in `--network-mode multi`, as the
east-west gateways. Ambient namespaces (`swarm-ambient-*`) have **no** Envoy
sidecar — ztunnel handles L4 there, and Envoy only appears if a waypoint is
deployed.

istiod is installed with `global.variant: "debug"`, so the proxy images include
`curl`, `tcpdump` and friends.

## Config dumps

```console
istioctl --context kind-pasta-1 pc listeners deploy/peer.swarm-sidecar-n1
istioctl --context kind-pasta-1 pc routes    deploy/peer.swarm-sidecar-n1
istioctl --context kind-pasta-1 pc clusters  deploy/peer.swarm-sidecar-n1
istioctl --context kind-pasta-1 pc endpoint  deploy/peer.swarm-sidecar-n1
istioctl --context kind-pasta-1 pc secret    deploy/peer.swarm-sidecar-n1
```

Dump the raw config of a gateway:
```console
k --context kind-pasta-1 -n istio-system exec deploy/istio-nsgw -- \
  curl -s localhost:15000/config_dump | istioctl pc listeners --file -
```

## Log levels

```console
istioctl --context kind-pasta-1 pc log deploy/peer.swarm-sidecar-n1 --level debug
k --context kind-pasta-1 -n swarm-sidecar-n1 logs -f deploy/peer -c istio-proxy
```

## Admin interface

```console
istioctl --context kind-pasta-1 dashboard envoy deploy/peer.swarm-sidecar-n1
```

Dump the `common_tls_context` of a given cluster (note the `<cell>.local`
suffix instead of `cluster.local`):
```console
k --context kind-pasta-1 -n swarm-sidecar-n1 exec deploy/peer -c istio-proxy -- \
curl -s localhost:15000/config_dump | jq '
  .configs[] |
  select(."@type"=="type.googleapis.com/envoy.admin.v3.ClustersConfigDump") |
  .dynamic_active_clusters[] |
  select(.cluster.name=="outbound|80||peer.swarm-sidecar-n1.svc.pasta.local") |
  .cluster.transport_socket_matches[] |
  select(.name=="tlsMode-istio") |
  .transport_socket.typed_config.common_tls_context
'
```

Drain every TCP connection (useful to force new TLS handshakes):
```console
k --context kind-pasta-1 -n swarm-sidecar-n1 exec deploy/peer -c istio-proxy -- \
  curl -X POST localhost:15000/quitquitquit
```

List the listening ports of a gateway:
```console
k --context kind-pasta-1 -n istio-system exec deploy/istio-nsgw -- \
  netstat -tuanp | grep LISTEN | sort -u
```

## Metrics

The `otelco-node` collector scrapes `/stats/prometheus` on every pod exposing a
`*-envoy-prom` port, so the same data is available in Prometheus. To look at it
raw:
```console
k --context kind-pasta-1 -n swarm-sidecar-n1 exec deploy/peer -c istio-proxy -- \
  curl -s localhost:15000/stats/prometheus | head
```
