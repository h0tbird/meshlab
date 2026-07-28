# Workloads

The lab does not deploy the usual `httpbin`/`sleep` samples. Instead, the
`deploy-workloads` section uses [k-swarm](https://github.com/h0tbird/k-swarm)'s
`swarmctl` CLI to fill the mesh with synthetic peers that continuously call each
other, so there is always real east-west traffic to observe.

## What gets deployed

On every workload cluster (`pasta-*`, and `pizza-*` with `--cell-count 2`):

| Namespace          | Contents                                     |
| ------------------ | -------------------------------------------- |
| `swarm-informer`   | The informer that tells the peers about each other. |
| `swarm-ambient-n1` | A `peer` Deployment (2 replicas) + Service, ambient data plane. |
| `swarm-ambient-n2` | Same, ambient. |
| `swarm-sidecar-n1` | Same, sidecar data plane. |
| `swarm-sidecar-n2` | Same, sidecar. |

Namespaces follow `swarm-<dataplane-mode>-n<index>`; every workload pod is the
`peer` app (`app=peer`), so it is a full 8-peer mesh per cell (2 clusters × 2
modes × 2 namespaces).

The exact invocations live in `bin/meshlab` (`deploy-workloads`) and boil down
to:

```console
swarmctl --context 'pasta-*|pizza-*' i --istio-revision stable --dataplane-mode ambient --ingress-mode none --multi-cluster
swarmctl --context 'pasta-*|pizza-*' w 1:2 --istio-revision stable --dataplane-mode ambient --ingress-mode none --multi-cluster --log-responses --disable-keepalives
swarmctl --context 'pasta-*|pizza-*' w 1:2 --istio-revision stable --dataplane-mode sidecar --ingress-mode none --multi-cluster --log-responses --disable-keepalives
```

Two flags are worth calling out:

- `--multi-cluster` makes the peers target their counterparts in the sibling
  cluster, which is what actually exercises the east-west path.
- `--disable-keepalives` is **load bearing**. ztunnel is an L4 proxy: it picks
  an upstream endpoint once per TCP connection, so a client reusing a
  keep-alive connection pins every request to a single endpoint and the traffic
  spread becomes meaningless. See `docs/single-network-mode.md`.

## Inspecting the peers

```console
k --context kind-pasta-1 get ns | grep swarm
k --context kind-pasta-1 -n swarm-ambient-n1 get pods -l app=peer
```

Each peer logs one JSON `hop` line per request, with `src.cluster`,
`src.namespace`, `dst.cluster`, `dst.namespace` and `http.status`:

```console
k --context kind-pasta-1 -n swarm-ambient-n1 logs -l app=peer -c manager --tail 20
```

## Connectivity matrix

Those `hop` lines are what the `connectivity-matrix` skill aggregates into an
8×8 table of which `(src peer, dst peer)` pairs are succeeding inside a cell:

```console
.github/skills/connectivity-matrix/gen-matrix.sh
```

> The script swallows `kubectl` errors, so an all-❌ matrix usually means it
> could not reach the clusters (for example when run in a sandbox that hides
> `~/.kube/config`) rather than a real outage. Sanity check with
> `k --context kind-pasta-1 -n swarm-ambient-n1 get pods -l app=peer` first.
