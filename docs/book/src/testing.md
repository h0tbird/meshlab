# Testing

The lab generates its own traffic: the [k-swarm peers](./components/workloads.md)
continuously call each other, both within a cluster and across the clusters of a
cell. Testing is therefore mostly a matter of *reading* what is already
happening.

Note that the peers are deployed with `--ingress-mode none`, so no
`Gateway`/`HTTPRoute` is attached to the north-south gateway by default. The
`istio-nsgw` deployment exists (with the custom bootstrap from `conf/istio`) but
serves nothing until you add routes yourself.

## Intra-cell connectivity matrix

The fastest end-to-end check is the 8×8 matrix built from the peers' `hop`
logs:

```console
.github/skills/connectivity-matrix/gen-matrix.sh
```

Each axis label is a `(cluster, namespace)` peer — `p1/am1` is
`pasta-1`/`swarm-ambient-n1` — and an intersection is ✅ when at least one
observed hop returned a `2xx`/`3xx`.

## Ad-hoc requests

From a sidecar peer to a peer in the other namespace (note the `pasta.local`
DNS suffix):

```console
k --context kind-pasta-1 -n swarm-sidecar-n1 exec deploy/peer -c manager -- \
  curl -s peer.swarm-ambient-n1.svc.pasta.local/data
```

Repeat it enough times to see the cross-cluster spread. Because ztunnel load
balances per **connection**, use a fresh connection each time or you will pin
every request to a single endpoint:

```console
for i in $(seq 20); do
  k --context kind-pasta-1 -n swarm-ambient-n1 exec deploy/peer -c manager -- \
    curl -s --no-keepalive peer.swarm-sidecar-n1.svc.pasta.local/data
done | jq -r '"\(.cluster)/\(.pod)"' | sort | uniq -c
```

## Verify the federation

```console
istioctl --context kind-pasta-1 remote-clusters
istioctl --context kind-pasta-1 proxy-status
```

Endpoints of a service as seen by a sidecar (should list pods from both
clusters of the cell):
```console
istioctl --context kind-pasta-1 pc endpoint deploy/peer.swarm-sidecar-n1 | grep peer
```

Same for ambient — this is what breaks first when cross-cluster ambient
discovery is off:
```console
istioctl --context kind-pasta-1 ztunnel-config service | grep swarm-ambient
istioctl --context kind-pasta-1 ztunnel-config workload | grep pasta-2
```

## Verify mTLS identities

```console
istioctl --context kind-pasta-1 pc secret deploy/peer.swarm-sidecar-n1 -o json |
  jq -r '.dynamicActiveSecrets[] | select(.name=="default") |
         .secret.tlsCertificate.certificateChain.inlineBytes' |
  base64 -d | step certificate inspect --bundle
```

The SAN should be
`spiffe://pasta.local/ns/swarm-sidecar-n1/sa/<serviceaccount>` — per-cell trust
domain, per-cluster intermediate CA, shared `mesh` root.
