# Load balancers

kind has no cloud controller, so `Service` objects of type `LoadBalancer` would
stay `<pending>` forever. The lab runs
[cloud-provider-kind](https://github.com/kubernetes-sigs/cloud-provider-kind)
instead: a single `kindccm` container, started by the `cloud-provider-kind`
section of `bin/meshlab` and attached to the Docker `kind` network. It watches
every kind cluster, assigns an IP from that network to each `LoadBalancer`
service, and runs an Envoy container to proxy that IP to the backing pods.

(The lab previously ran on k3s and its `klipper-lb`; neither is used any more.)

List the assigned IPs across all clusters:
```console
ml    # prints pods and LoadBalancer services per cluster
```

Or per cluster:
```console
k --context kind-mnger-1 get svc -A --field-selector=spec.type=LoadBalancer
k --context kind-pasta-1 get svc -A --field-selector=spec.type=LoadBalancer
```

See the controller container and its logs:
```console
docker ps --filter name=kindccm
docker logs -f kindccm
```

## Reaching the services from the host

The assigned IPs live on the Docker `kind` network and are reachable from the
dev container, but not necessarily from the host browser. The `publish-ports`
section therefore runs a `socat` forwarder per UI:

| Service        | Cluster / namespace       | Local port |
| -------------- | ------------------------- | ---------- |
| Argo CD        | `mnger-1` / `argocd`      | 8080       |
| Argo Workflows | `mnger-1` / `argowf`      | 8081       |
| Vault          | `mnger-1` / `vault`       | 8082       |
| Prometheus     | `mnger-1` / `monitoring`  | 8083       |
| Grafana        | `mnger-1` / `monitoring`  | 8084       |
| Kiali          | `mnger-1` / `monitoring`  | 8085       |

Re-publish them after a restart:
```console
meshlab run publish-ports
```
