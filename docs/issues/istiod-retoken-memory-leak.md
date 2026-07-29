# istiod memory leak on remote-secret re-tokening (Istio 1.30.3)

> Does frequent re-tokening of a multicluster remote secret leak memory in `istiod`?
>
> **Yes.** Every token rotation rebuilds the whole remote-cluster stack and the
> teardown is incomplete. In this lab each rotation permanently costs
> **~2.3 MB of live heap and ~30 goroutines**, with no plateau.

## TL;DR

| | |
|---|---|
| Verdict | Reproducible, unbounded leak |
| Trigger | Any change to the `istio/multiCluster` secret payload (a new SA token is enough) |
| Cost per rotation | ~2.3 MB live heap, ~30 goroutines, ~25 leaked KRT collections |
| Version | `istio/istio` tag `1.30.3` (commit `56df41f63e`), ambient multi-primary multi-network |
| Recovers? | No. Heap and goroutines stay at the new level after the rotations stop |
| Already-shipped KRT fixes | `#60554`/`#60657` (`e581ae2842`) *is* in 1.30.3 — this is a **different** leak |
| Closest upstream issue | [istio/istio#60033](https://github.com/istio/istio/issues/60033) (open) |

## Lab facts

| Item | Value |
|---|---|
| istiod | built from tag `1.30.3`, revision `1-30-3`, deployment `istiod-1-30-3` |
| Clusters | `kind-pasta-1` (network `pasta-1`), `kind-pasta-2` (network `pasta-2`) |
| Mesh | mesh ID `pasta`, ambient + sidecar, `AMBIENT_ENABLE_MULTI_NETWORK=true` |
| Remote secret | `istio-remote-secret-pasta-2` in `istio-system` on `pasta-1` |
| Workloads | 8 k-swarm `peer` deployments (4 namespaces × 2 clusters) |
| Control | `pasta-2` holds no remote secret and shows **no** leak |

## Reproduction

```sh
# in the meshlab devcontainer
kubectl --context kind-pasta-1 -n istio-system \
  port-forward deployments/istiod-1-30-3 9090:8080 &

HEAP_PROFILE=true bin/retoken patch
```

`bin/retoken patch` runs 200 iterations of:

1. read `istio-remote-secret-pasta-2` from `pasta-1`,
2. mint a fresh `istio-reader-service-account` token on `pasta-2`,
3. splice it into `.users[0].user.token` of the embedded kubeconfig,
4. `kubectl patch` the secret,
5. sleep 5s; every 10 iterations pull `/debug/pprof/heap?gc=1`.

Nothing else in either cluster changes. This is exactly what an external token
rotator (cert-manager, sealed-secrets, a CronJob, a bound-token refresher…) does
in production.

## Evidence

### Live heap (`pprof -inuse_space`, all samples taken with `?gc=1`)

| Sample | Rotations | Live heap |
|---|---|---|
| 0 | 0 | 35.2 MB |
| 5 | 50 | 153.3 MB |
| 10 | 100 | 267.5 MB |
| 15 | 150 | 387.4 MB |
| 20 | 200 | 501.1 MB |

Increments per 50 rotations: 118.1 / 114.3 / 119.9 / 113.7 MB — dead linear,
**~2.33 MB per rotation**, no sign of levelling off. The istiod pod never
restarted during the run.

### Goroutines

```
1746  flat for the 15 min before the test
7746  after 200 rotations         → ~30 goroutines leaked per rotation
```

Breakdown of the final 7743 goroutines:

| Count | Frame |
|---|---|
| 4388 | `krt.(*processorListener[…]).run` / `.pop` — `pkg/kube/krt/processor.go:210,241` |
| 1003 | `client-go tools/cache.(*processorListener).pop` |
| 346 | istio queues (`pkg/queue`, `workqueue`) |
| 224 | client-go reflector / shared processor plumbing |

### Where the heap goes (sample 20, 501 MB total)

```
202.9 MB (40.5%)  v1.(*ObjectMeta).Unmarshal
                    ├── 175.3 MB  PartialObjectMetadata   (metadata informers / CRD watcher)
                    ├──   9.0 MB  Service
                    ├──   7.5 MB  Pod
                    └──   7.5 MB  EndpointSlice
 94.6 MB (18.9%)  buffer.NewTypedRingGrowing[interface{}]  (event ring buffers)
                    ├──  29.0 MB  client-go NewRingGrowing
                    ├──  17.3 MB  krt.newProcessListener[ClusterNetwork]
                    ├──  15.3 MB  krt.newProcessListener[*MeshConfig]
                    ├──   8.1 MB  krt.newProcessListener[Waypoint]
                    ├──   5.6 MB  krt.newProcessListener[string]
                    ├──   4.1 MB  krt.newProcessListener[NetworkGateway]
                    ├──   3.6 MB  krt.newProcessListener[*Pod]
                    ├──   2.5 MB  krt.newProcessListener[Node]
                    ├──   2.0 MB  krt.newProcessListener[*MeshNetworks]
                    └──   1.5 MB  krt.newProcessListener[Authorization]
 13.8 MB           grpc mem.(*sizedBufferPool).Get
 12.5 MB           v1.(*Secret).Unmarshal
  6.0 MB           client-go rest.NewRESTClient
```

The `newProcessListener[…]` type parameters map 1:1 onto the **global** collections
that per-cluster collections `Fetch` (see below), and `PartialObjectMetadata` is
the informer cache of the discarded `kube.Client`s.

### Metrics

`remote_cluster_secret_events_total{event="update"}` tracks the rotation count
exactly (87 at rotation 87, …). The KRT collection `uid` counter in the istiod
log went from 1544 to 3568 between rotation 5 and rotation 87 —
**~24.7 new KRT collections per rotation**.

Instrumented as a ratio:

```promql
sum by (k8s_cluster_name) (deriv(go_goroutines{job="istiod"}[10m]))
/ clamp_min(sum by (k8s_cluster_name)
    (rate(remote_cluster_secret_events_total{job="istiod",event="update"}[10m])), 0.001)
```

→ `pasta-1: 33.3`, `pasta-2: 0.53` (control).

## Diagnosis

### 1. A token change is a full cluster rebuild

`addRemoteConfig` in
[`pkg/kube/multicluster/secretcontroller.go`](../../istio/pkg/kube/multicluster/secretcontroller.go)
compares `sha256.Sum256(kubeConfig)` against the previous kubeconfig. A new token
changes the SHA, so the action becomes `Update`, not a no-op:

```go
if prev != nil && bytes.Equal(prev.kubeConfigSha[:], kubeConfigSha[:]) {
    // "skipping update (kubeconfig are identical)"
}
action = Update
remoteCluster, err = c.createRemoteCluster(kubeConfig, clusterID)  // brand new kube.Client
swap := c.cs.Swap(secretKey, clusterID, remoteCluster)
go remoteCluster.Run(c.meshWatcher, c.handlers, action, swap, c.debugger)
```

`Cluster.Run` then builds a fresh namespace filter, six informer-backed KRT
collections (`Namespaces`, `Pods`, `Gateways`, `Services`, `Nodes`,
`EndpointSlices`) plus everything the registered handlers derive from them —
in ambient multicluster that is ~25 collections, a per-cluster mesh watcher, new
queues, and a new set of client-go reflectors. This is the intended
make-before-break behaviour; the problem is the *break* half.

### 2. KRT dependency handlers are never unregistered

`collectionDependencyTracker.registerDependency`
([`pkg/kube/krt/collection.go:809`](../../istio/pkg/kube/krt/collection.go)):

```go
if !existed {
    syncer.WaitUntilSynced(i.stop)
    register(func(o []Event[any]) { i.queue.Push(...) }).WaitUntilSynced(i.stop)
}
```

`register` ends up in `RegisterBatch` on the **dependency** collection, which
calls `handlerSet.Insert(f, …, <dependency>.stop)` — the *dependency's* stop
channel, not the registrant's. `UnregisterHandler()` exists but is never called
from production code (only from krt internals and tests).

That is fine when both collections have the same lifetime. It is a leak when a
**per-cluster** collection fetches a **process-lifetime global** collection —
which is exactly what ambient multicluster does. From
[`pilot/pkg/serviceregistry/ambient/workloads.go:334`](../../istio/pilot/pkg/serviceregistry/ambient/workloads.go),
inside the nested `krt.NewCollection(clusters, func(ctx, c *multicluster.Cluster) …)`:

```go
PodWorkloads := krt.NewCollection(pods, podWorkloadBuilder(
    meshConfig,                                   // global
    globalNetworks.FetchLocalNetworkID,           // global
    localAuthorizationPolicies, localPeerAuths,   // global
    waypoints, globalWorkloadServices,            // global
    …
    func(ctx krt.HandlerContext) network.ID {
        nw := krt.FetchOne(ctx, globalNetworks.RemoteSystemNamespaceNetworks, …)
        …
    },
    globalNetworks.GatewaysByNetwork,              // global
), krt.WithName(fmt.Sprintf("PodWorkloads[%s]", c.ID)))
```

Each of those `Fetch`es installs a listener on a global collection. Every
listener is two goroutines (`processorListener.run` + `.pop`) and a 1024-slot
`buffer.NewTypedRingGrowing`, and its closure captures the per-cluster
collection. After the old cluster is stopped the listener is still in the global
collection's handler set, still holding the old per-cluster state alive.

This matches the profile exactly: the biggest leaked ring buffers are
`[ClusterNetwork]` (`RemoteSystemNamespaceNetworks`), `[*MeshConfig]` (global
mesh watcher), `[Waypoint]`, `[NetworkGateway]`, `[*MeshNetworks]`,
`[Authorization]`.

### 3. `krt.DebugHandler` is an append-only registry with no removal

[`pkg/kube/krt/debug.go`](../../istio/pkg/kube/krt/debug.go):

```go
type DebugHandler struct {
    debugCollections []DebugCollection
    mu               sync.RWMutex
}

func maybeRegisterCollectionForDebugging[T any](c Collection[T], handler *DebugHandler) {
    if handler == nil { return }
    cc := c.(internalCollection[T])
    handler.mu.Lock(); defer handler.mu.Unlock()
    handler.debugCollections = append(handler.debugCollections, DebugCollection{
        name: cc.name(), dump: cc.dump, uid: cc.uid(),
    })
}
```

There is **no** deregistration API in the package. It is called from every
collection constructor (`collection.go`, `informer.go`, `index.go`, `map.go`,
`join.go`, `mergejoin.go`, `nestedjoinmerge.go`, `singleton.go`, `static.go`),
and `pilot/pkg/bootstrap/options.go:153` sets
`p.KrtDebugger = new(krt.DebugHandler)` **unconditionally** — so it is always on
in production, not just when debugging.

Each retained `DebugCollection.dump` is a method value bound to the collection,
which transitively pins its indexes, its `kclient` and the underlying informer
`cache.Store`. That is the 175 MB of `PartialObjectMetadata` and the
Service/Pod/EndpointSlice caches: the informer *goroutines* do exit (the old
`Cluster.Stop()` does `close(c.stop)`), but their *caches* can never be
collected.

### 4. `informerFactory.Shutdown()` does not stop informers

[`pkg/kube/informerfactory/factory.go`](../../istio/pkg/kube/informerfactory/factory.go):

```go
func (f *informerFactory) Shutdown() {
    defer f.wg.Wait()
    f.lock.Lock(); defer f.lock.Unlock()
    f.shuttingDown = true
}
```

`client.Shutdown()` — called from `PendingClusterSwap.Complete()` and
`deleteCluster` — only refuses *new* starts and then blocks until the existing
informer goroutines exit on their own stop channels. Anything started with a
channel other than the swapped cluster's `c.stop` survives.

### 5. Possible orphaned pending swap (not yet proven)

`Component[T].clusterUpdated` in
[`pkg/kube/multicluster/component.go`](../../istio/pkg/kube/multicluster/component.go)
stores the pending swap as `m.pendingSwaps[clusterID]`. If a second update
arrives before the first swap has synced, the map entry is overwritten and the
first swap's `old` component is never closed. With a 5 s rotation interval this
is plausible but was not isolated.

## Incidental bugs found along the way

- **`/debug/krtz` returns HTTP 500.**
  `json: error calling MarshalJSON for type *krt.DebugHandler: … json: unsupported type: chan struct {}`.
  The collection dump cannot be serialised, so the one endpoint that would let an
  operator count registered collections is unusable.
- **`istiod_remote_cluster_sync_status` gets stuck on `closed`.**
  After a swap, `{cluster="pasta-2", status="closed"} = 1` while `status="synced" = 0`.
  `recordClusterSyncState` is keyed only by cluster ID, so the *old* cluster's
  `Stop()` (which records `closed`) overwrites the *new* cluster's `synced`.

## Mitigations while this is unfixed

- Rotate remote-secret tokens as rarely as the security policy allows. Every
  rotation is a full remote-cluster rebuild, not a cheap credential refresh.
- Prefer long-lived / bound service-account tokens for the remote reader SA, or a
  file-based `MULTICLUSTER_KUBECONFIG_PATH` source, over a controller that
  rewrites the secret.
- Make sure nothing else rewrites the `istio/multiCluster` secret — GitOps
  reconcilers, sealed-secrets, Kyverno mutations and cert-manager renewals all
  count, even if the resulting token is functionally equivalent.
- Alert on the leak directly:

  ```promql
  # goroutines leaked per remote-secret update
  deriv(go_goroutines{job="istiod"}[10m])
  / clamp_min(rate(remote_cluster_secret_events_total{job="istiod",event="update"}[10m]), 0.001)
  ```

  and on `rate(remote_cluster_secret_events_total{event="update"}[1h]) > 0`.
- Until a fix lands, a periodic istiod restart is the only way to reclaim the
  memory.

## Upstream context

- [#60033](https://github.com/istio/istio/issues/60033) — open, *"Istio Ambient
  mode multi-cluster memory leak"*. In the thread the maintainer writes:
  *"when we're rotating those secrets, I think we might not be releasing the
  resources from the old ones"* — this reproduction confirms that hypothesis for
  the remote secret specifically. The reporter's environment churns secrets via
  sealed-secrets/Kyverno.
- [#60043](https://github.com/istio/istio/issues/60043) / PR
  [#60554](https://github.com/istio/istio/pull/60554) *"Fix for leaking indexes
  in KRT"* — cherry-picked as #60657, commit `e581ae2842`, **already in 1.30.3**.
  This leak is separate.
- [#60909](https://github.com/istio/istio/issues/60909) — `NamespaceController`
  leaks informer event handlers when stopped before caches sync. Same family,
  different component.
- No upstream issue or PR mentions `DebugHandler` / `debugCollections` retention
  or the missing `UnregisterHandler` on cross-lifetime KRT dependencies.

## Dashboard

`grafana/memory-leak.json` (Grafana dashboard `adtlb8r`, *Memory leak*) gained
six panels for this investigation:

| Panel | What it shows |
|---|---|
| Goroutines | `go_goroutines` — the clearest leak signal |
| Go heap / stack / RSS | `go_memstats_heap_inuse_bytes`, `go_memstats_stack_inuse_bytes`, `process_resident_memory_bytes` |
| Remote cluster secret events | `rate(remote_cluster_secret_events_total[…])` by event |
| Remote cluster sync status | `istiod_remote_cluster_sync_status`, `istiod_managed_clusters` |
| Leak per re-tokening | growth rate ÷ secret-update rate — bytes and goroutines per rotation |
| Live heap objects | `go_memstats_heap_objects` |

The dashboard is provisioned by `grafana-git-sync` from `grafana/` in this repo,
so edit the JSON here rather than in the Grafana UI — the API rejects direct
writes with `403 Can not remove resource manager from resource`. The changes
land in Grafana once the commit is pushed and git-sync reconciles.
