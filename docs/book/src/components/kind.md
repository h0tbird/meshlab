# kind

[kind](https://kind.sigs.k8s.io) runs Kubernetes clusters as Docker containers.
The lab used to provision VMs; today every cluster is a single-node kind
cluster and there is no VM, hypervisor or cloud-init layer left.

Clusters are created by the `create-clusters` section of `bin/meshlab`. Which
ones exist depends on `--cell-count`:

| Cluster   | Cell    | Pod CIDR        | Service CIDR     | DNS domain    |
| --------- | ------- | --------------- | ---------------- | ------------- |
| `mnger-1` | `mnger` | `10.41.0.0/16`  | `10.141.0.0/16`  | `mnger.local` |
| `pasta-1` | `pasta` | `10.51.0.0/16`  | `10.151.0.0/16`  | `pasta.local` |
| `pasta-2` | `pasta` | `10.52.0.0/16`  | `10.152.0.0/16`  | `pasta.local` |
| `pizza-1` | `pizza` | `10.61.0.0/16`  | `10.161.0.0/16`  | `pizza.local` |
| `pizza-2` | `pizza` | `10.62.0.0/16`  | `10.162.0.0/16`  | `pizza.local` |

The CIDRs come from the `POD_CIDR` and `SVC_CIDR` maps in `lib/common.sh`; they
never overlap so the clusters of a cell can be wired into a
[flat L3 network](./flat-network.md). The kubeadm `networking.dnsDomain` is set
to `<cell>.local`, which is why istiod is configured with a matching
`global.proxy.clusterDomain`.

All node containers are attached to the Docker `kind` network, together with
the [zot](./pull-through.md) cache and the `kindccm`
[load balancer](./load-balancers.md) containers.

## Everyday commands

List the clusters:
```console
kind get clusters
```

Note that kubeconfig contexts carry the `kind-` prefix:
```console
k config get-contexts
k --context kind-pasta-1 get nodes -o wide
```

Get a shell on a node (each cluster has a single `<cluster>-control-plane`
container):
```console
docker exec -it pasta-1-control-plane bash
```

Inspect the Docker network the clusters share:
```console
docker network inspect kind | jq -r '.[].Containers[].Name'
```

Delete everything (also stops zot, `kindccm`, Tilt and the `socat` forwards):
```console
meshlab delete
```

> Node containers are not restart-safe by design: the static routes installed by
> `setup-flat-network` and the containerd registry config live inside the node
> container. If a node restarts, re-run `meshlab run setup-flat-network` and
> `meshlab run add-registries-to-containerd`.
