# istiod memory leak on remote-secret re-tokening (Istio 1.30.3)

> **Update:** the leak was tracked down and fixed on 1.31.0-alpha.2 — see
> [Fixing the istiod re-tokening leak](istiod-retoken-memory-leak-fix.md).

> Does frequent re-tokening of a multicluster remote secret leak memory in `istiod`?
>
> **Yes.** Every token rotation rebuilds the whole remote-cluster stack and the
> teardown is incomplete. In this lab each rotation permanently costs
> **~2.4 MB of live heap and exactly 30 goroutines**, with no plateau.

## TL;DR

| | |
|---|---|
| Verdict | Reproducible, unbounded leak |
| Trigger | Any change to the `istio/multiCluster` secret payload (a new SA token is enough) |
| Cost per rotation | ~2.4 MB live heap, 30 goroutines, ~35 leaked KRT collections |
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
# in the meshlab devcontainer, against a freshly restarted istiod
OUTDIR=/tmp/leak ITERATIONS=200 INTERVAL=5 SAMPLE_EVERY=10 bin/retoken
```

[`bin/retoken`](../../bin/retoken) discovers the istiod deployment, forwards its
debug (`8080`) and monitoring (`15014`) ports, and then repeats:

1. read `istio-remote-secret-pasta-2` from `pasta-1`,
2. mint a fresh `istio-reader-service-account` token on `pasta-2`,
3. splice it into `.users[0].user.token` of the embedded kubeconfig,
4. `kubectl patch` the secret,
5. sleep 5 s.

Every 10 rotations it appends `go_goroutines`,
`go_memstats_heap_inuse_bytes` and `process_resident_memory_bytes` to a CSV and
pulls `/debug/pprof/heap?gc=1` and `/debug/pprof/goroutine`.

Nothing else in either cluster changes. This is exactly what an external token
rotator (cert-manager, sealed-secrets, a CronJob, a bound-token refresher…) does
in production.

### Bisecting

`bin/retoken bisect` turns the same measurement into a single pass/fail probe
for one istio commit: it builds `pilot-discovery`, waits until Tilt has
live-synced that exact binary into istiod and the goroutine count has gone flat,
rotates the token, and reads the goroutines-per-rotation slope as a verdict —
`0` when clean, `1` when leaking, `125` when the commit cannot be built or
measured.

```sh
cd /workspaces/istio
git bisect start <bad-rev> <good-rev>
git bisect run /workspaces/meshlab/bin/retoken bisect
```

Every run appends its numbers to `/tmp/retoken-results.csv`, so a bisect that
finds no transition still leaves proof that the behaviour is uniform. Each phase
— build, deploy, settle, rotate, verdict — is also annotated on the "Memory
leak" dashboard, so a running bisect narrates itself in Grafana.

The run reported below ran **2026-07-29 13:03:28Z → 13:20:23Z** against pod
`istiod-1-30-3-7f8b7fcd6f-tkdwq`, which had been restarted and left to settle
beforehand and recorded **0 restarts** throughout.

## Evidence

### Live heap (`pprof -inuse_space`, all samples taken with `?gc=1`)

| Sample | Rotations | Live heap | Δ |
|---|---|---|---|
| 0 | 0 | 37.6 MB | — |
| 5 | 50 | 165.0 MB | +127.5 MB |
| 10 | 100 | 282.0 MB | +117.0 MB |
| 15 | 150 | 397.9 MB | +115.9 MB |
| 20 | 200 | 525.9 MB | +128.0 MB |

Dead linear — **~2.44 MB of live heap per rotation**, no sign of levelling off.
Resident memory over the same window went 143 MB → 822 MB (+3.4 MB per
rotation); the gap between the two is garbage that has not been collected yet.

### Goroutines

```
1748  flat before the test
7746  after 200 rotations
```

Exactly **+30.0 goroutines per rotation**. `pprof -diff_base` between sample 0
and sample 20 breaks that down into suspiciously round numbers — every leaked
frame is an exact multiple of 200, i.e. one leaked listener per rotation:

| Δ goroutines | Per rotation | Frame |
|---|---|---|
| 1600 | 8 | `krt.processorListener[ClusterNetwork].run` / `.pop` |
| 1600 | 8 | `client-go cache.processorListener.run` / `.pop` |
| 1200 | 6 | `krt.processorListener[*MeshConfig].run` / `.pop` |
| 400 | 2 | `krt.processorListener[NetworkGateway].run` / `.pop` |
| 400 | 2 | `krt.processorListener[Node].run` / `.pop` |
| 400 | 2 | `krt.processorListener[Authorization].run` / `.pop` |
| 200 | 1 | `krt.manyCollection[…Node].runQueue` |
| 200 | 1 | `istio.io/istio/pkg/queue.(*queueImpl).Run` |
| **6000** | **30** | total |

Each krt `processorListener` is two goroutines (`run` + `pop`) plus a 1024-slot
ring buffer, so this is **10 leaked krt listeners plus 4 leaked client-go
listeners per rotation**. The type parameters are not arbitrary:
`ClusterNetwork`, `*MeshConfig`, `NetworkGateway`, `Node` and `Authorization`
are precisely the **global**, process-lifetime collections that the
**per-cluster** workload builder fetches — see Diagnosis 2.

### Where the heap goes (sample 20, 525.9 MB total)

Two cost centres account for 60% of the live heap. First, the informer caches of
the discarded `kube.Client`s:

```
275.5 MB (52.4%)  watch.(*StreamWatcher).receive          [cum]
220.6 MB (41.9%)  └── v1.(*ObjectMeta).Unmarshal
                        ├── 193.0 MB  PartialObjectMetadata
                        ├──   7.5 MB  Service
                        ├──   7.5 MB  Pod
                        ├──   5.0 MB  EndpointSlice
                        ├──   3.5 MB  Secret
                        ├──   2.5 MB  Namespace
                        └──   1.6 MB  ConfigMap
```

Second, the ring buffers of the leaked event listeners:

```
 96.7 MB (18.4%)  buffer.NewTypedRingGrowing[interface{}]
                    ├──  25.4 MB  client-go NewRingGrowing
                    ├──  18.3 MB  krt.newProcessListener[*MeshConfig]
                    ├──  14.3 MB  krt.newProcessListener[ClusterNetwork]
                    ├──   9.2 MB  krt.newProcessListener[…]
                    ├──   8.1 MB  krt.newProcessListener[Waypoint]
                    ├──   4.1 MB  krt.newProcessListener[string]
                    ├──   4.1 MB  krt.newProcessListener[*MeshNetworks]
                    ├──   4.1 MB  krt.newProcessListener[*Pod]
                    ├──   4.1 MB  krt.newProcessListener[Authorization]
                    ├──   2.5 MB  krt.newProcessListener[Node]
                    ├──   1.5 MB  krt.newProcessListener[NetworkGateway]
                    └──   1.0 MB  krt.newProcessListener[Config], [gateway route]
```

The profile names the mechanism directly:
`krt.(*collectionDependencyTracker[…]).registerDependency` holds **39.6 MB**
cumulative, and `ambient.MergedGlobalWorkloadsCollection.func2.podWorkloadBuilder.14`
— the closure that fetches `RemoteSystemNamespaceNetworks` — holds **44.0 MB**.

### KRT collections

The krt collection `uid` counter in the istiod log went **1696 → 7636** between
rotation ~32 and rotation 200: **~35 new KRT collections per rotation**, none of
which are ever deregistered (Diagnosis 3). Extrapolating back, istiod started the
run with roughly 560.

### Metrics

`remote_cluster_secret_events_total{event="update"}` tracks the rotation count
exactly. Instrumented as a ratio:

```promql
sum by (k8s_cluster_name) (deriv(go_goroutines{job="istiod"}[10m]))
/ clamp_min(sum by (k8s_cluster_name)
    (rate(remote_cluster_secret_events_total{job="istiod",event="update"}[10m])), 0.001)
```

→ ~30 on `pasta-1`, ~0 on `pasta-2` (the control cluster, which holds no remote
secret).

### Nothing is reclaimed afterwards

Fifteen minutes after the last rotation, with a forced GC in between,
`go_goroutines` sits at **7747** and `go_memstats_heap_inuse_bytes` at
**615 MB** — against a pre-test baseline of 1748 goroutines and 48 MB. The leak
is permanent for the life of the process.

## Diagnosis

### 1. A token change is a full cluster rebuild

`addRemoteConfig` in
[`pkg/kube/multicluster/secretcontroller.go#L439-L473`](https://github.com/istio/istio/blob/1.30.3/pkg/kube/multicluster/secretcontroller.go#L439-L473)
compares `sha256.Sum256(kubeConfig)` against the previous kubeconfig. A new token
changes the SHA, so the early-out is skipped and the action stays `Update`:

```go
if prev = c.cs.Get(configKey, cluster.ID(clusterID)); prev != nil {
    action = Update
    kubeConfigSha := sha256.Sum256(kubeConfig)
    if bytes.Equal(kubeConfigSha[:], prev.kubeConfigSha[:]) {
        logger.Infof("skipping update (kubeconfig are identical)")
        continue
    }
    // Don't stop the previous cluster here - it will be stopped after the new cluster syncs.
}
...
remoteCluster, err := c.createRemoteCluster(name, kubeConfig, clusterID)  // brand new kube.Client
swap := c.cs.Swap(configKey, remoteCluster.ID, remoteCluster)
go func() {
    remoteCluster.Run(c.meshWatcher, c.handlers, action, swap, c.debugger)
}()
```

`Cluster.Run` then builds a fresh namespace filter, six informer-backed KRT
collections (`Namespaces`, `Pods`, `Gateways`, `Services`, `Nodes`,
`EndpointSlices`) plus everything the registered handlers derive from them —
in ambient multicluster that is ~25 collections, a per-cluster mesh watcher, new
queues, and a new set of client-go reflectors. This is the intended
make-before-break behaviour; the problem is the *break* half.

### 2. KRT dependency handlers are never unregistered

`collectionDependencyTracker.registerDependency`
([`pkg/kube/krt/collection.go#L811-L831`](https://github.com/istio/istio/blob/1.30.3/pkg/kube/krt/collection.go#L811-L831)):

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
[`pilot/pkg/serviceregistry/ambient/workloads.go#L333-L367`](https://github.com/istio/istio/blob/1.30.3/pilot/pkg/serviceregistry/ambient/workloads.go#L333-L367),
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
listener is two goroutines
([`processorListener.pop`](https://github.com/istio/istio/blob/1.30.3/pkg/kube/krt/processor.go#L203)
and [`.run`](https://github.com/istio/istio/blob/1.30.3/pkg/kube/krt/processor.go#L239))
and a 1024-slot
[`buffer.NewTypedRingGrowing`](https://github.com/istio/istio/blob/1.30.3/pkg/kube/krt/processor.go#L168-L184),
and its closure captures the per-cluster collection. After the old cluster is
stopped the listener is still in the global collection's handler set, still
holding the old per-cluster state alive.

The goroutine diff confirms this listener-for-listener: the leaked
`processorListener` type parameters are exactly `ClusterNetwork`
(`RemoteSystemNamespaceNetworks` / `FetchLocalNetworkID`), `*MeshConfig` (the
global mesh watcher), `NetworkGateway` (`GatewaysByNetwork`), `Node` and
`Authorization` — every one of them a global fetched by the per-cluster builder
above. The heap profile shows the same set of ring buffers, plus `Waypoint`,
`*MeshNetworks` and `string`.

### 3. `krt.DebugHandler` is an append-only registry with no removal

[`pkg/kube/krt/debug.go#L22-L26`](https://github.com/istio/istio/blob/1.30.3/pkg/kube/krt/debug.go#L22-L26)
and [`#L64-L77`](https://github.com/istio/istio/blob/1.30.3/pkg/kube/krt/debug.go#L64-L77):

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
and [`pilot/pkg/bootstrap/options.go#L153`](https://github.com/istio/istio/blob/1.30.3/pilot/pkg/bootstrap/options.go#L153)
sets `p.KrtDebugger = new(krt.DebugHandler)` **unconditionally** — so it is
always on in production, not just when debugging.

Each retained `DebugCollection.dump` is a method value bound to the collection,
which transitively pins its indexes, its `kclient` and the underlying informer
`cache.Store`. That is the 193 MB of `PartialObjectMetadata` and the
Service/Pod/EndpointSlice caches: the informer *goroutines* do exit (the old
`Cluster.Stop()` does `close(c.stop)`), but their *caches* can never be
collected.

### 4. `informerFactory.Shutdown()` does not stop informers

[`pkg/kube/informerfactory/factory.go#L243-L249`](https://github.com/istio/istio/blob/1.30.3/pkg/kube/informerfactory/factory.go#L243-L249):

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

### 5. Orphaned pending swaps when rotations outpace sync

The old component is closed in exactly one place —
[`pendingSwap.HasSynced()`](https://github.com/istio/istio/blob/1.30.3/pkg/kube/multicluster/component.go#L59-L77):

```go
func (p *pendingSwap[T]) HasSynced() bool {
    if !p.new.HasSynced() {
        return false
    }
    // New component is synced, finalize the swap by closing the old one
    p.mu.Lock()
    if p.hasOld {
        p.old.Close()
        ...
```

but [`Component[T].clusterUpdated`](https://github.com/istio/istio/blob/1.30.3/pkg/kube/multicluster/component.go#L130-L161)
overwrites the map entry unconditionally:

```go
m.pendingSwaps[cluster.ID] = ps
```

So if a second rotation arrives before the previous swap's new component has
synced, the previous `pendingSwap` is dropped on the floor and its `old`
component is never `Close()`d. At a 5 s rotation interval against a cluster that
takes longer than that to sync, this is the common case rather than the corner
case. This was not isolated separately from the handler leak.

## Incidental bugs found along the way

- **`/debug/krtz` returns HTTP 500.**
  `json: error calling MarshalJSON for type *krt.DebugHandler: json: error calling MarshalJSON for type krt.DebugCollection: json: unsupported type: chan struct {}`.
  The collection dump cannot be serialised, so the one endpoint that would let an
  operator count registered collections is unusable.
- **`istiod_remote_cluster_sync_status` gets stuck on `closed`.**
  After a swap, `{cluster="pasta-2", status="closed"} = 1` while `status="synced" = 0`,
  even though the remote cluster is healthy and serving.
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

  Anything consistently above ~1 means goroutines are being leaked per rotation;
  in this lab it sits at 30. Also alert on
  `rate(remote_cluster_secret_events_total{event="update"}[1h]) > 0`.
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

`grafana/memory-leak.json` (Grafana dashboard `adtlb8r`, *Memory leak*) is
dedicated to this investigation:

| Panel | What it shows |
|---|---|
| Goroutines | `go_goroutines` — the clearest leak signal |
| Go heap / stack / RSS | `go_memstats_heap_inuse_bytes`, `go_memstats_stack_inuse_bytes`, `process_resident_memory_bytes` |
| Remote cluster secret events | `rate(remote_cluster_secret_events_total[…])` by event |
| Managed clusters | `istiod_managed_clusters` — the control variable, flat while the leak grows; `istiod_remote_cluster_sync_status` alongside it as an exhibit of the stuck-on-`closed` bug |
| Leak per re-tokening | growth rate ÷ secret-update rate — bytes and goroutines per rotation |
| Live heap objects | `go_memstats_heap_objects` |

The dashboard is provisioned by `grafana-git-sync` from `grafana/` in this repo,
so edit the JSON here rather than in the Grafana UI — the API rejects direct
writes with `403 Can not remove resource manager from resource`. The changes
land in Grafana once the commit is pushed and git-sync reconciles.
