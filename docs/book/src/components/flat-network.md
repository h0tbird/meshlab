# Flat network

Each cell is a flat L3 network. Clusters run the default kindnet CNI with
kube-proxy enabled, and `setup-flat-network` adds static routes between the
sibling clusters of a cell so their pod and service CIDRs are directly routable.
This replaces Cilium ClusterMesh as the source of cross-cluster pod-to-pod
reachability.

Each cluster is given a unique pod and service CIDR (see `POD_CIDR` / `SVC_CIDR`
in `lib/common.sh`) so the ranges never overlap inside a cell.

Show the routes installed on a cluster node:
```console
docker exec pasta-1-control-plane ip route
```

Verify cross-cluster pod reachability (from a pod in `pasta-1` to a pod IP in
`pasta-2`):
```console
k --context pasta-1 exec deploy/<app> -- curl -s <pasta-2-pod-ip>:<port>
```

> Routes are added via `docker exec ... ip route replace` and live only in the
> node container's routing table. They are lost if a node container restarts;
> re-run `setup-flat-network` (`ml run setup-flat-network`) to reinstall them.
