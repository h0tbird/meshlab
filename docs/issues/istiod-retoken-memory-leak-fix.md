# Fixing the istiod re-tokening leak (Istio 1.31.0-alpha.2)

> Follow-up to [istiod memory leak on remote-secret re-tokening](istiod-retoken-memory-leak.md),
> which characterised the leak on 1.30.3. This document records how it was
> tracked down to three distinct causes on `1.31.0-alpha.2`, what was changed,
> and what the numbers look like afterwards.

## TL;DR

| | before | after |
|---|---|---|
| goroutines per rotation | **+30.8** | **~0** (flat 1617-1623 over 17 rotations) |
| live krt dependency handlers | +27 per rotation, never freed | flat at 174 |
| running krt queues | +1 per rotation | flat at 96 |
| retained informer cache (post-GC) | ~1.4 MB per rotation | ~0.14 MB per rotation |
| `DebugHandler` entries | append-only, 1 → 836 in 24 rotations | pruned on stop |

Three independent bugs, all of which had to be fixed to make the numbers flat:

1. **krt never unregistered `Fetch` dependencies** — a per-cluster collection
   that fetches a process-lifetime global left its listener behind forever.
2. **`krt.DebugHandler` was an append-only registry** — it pinned every
   collection ever created, including the caches behind them.
3. **`ambient/GlobalNodeLocalityWithCluster` used the wrong stop channel** — one
   per-cluster collection was built with the process-lifetime stop, so its queue
   never exited and it kept the dead cluster's client, informers and caches
   reachable. This was the one that actually held the megabytes.

Lab: `1.31.0-alpha.2` (`1bb542cb7b`), `kind-pasta-1` + `kind-pasta-2`, ambient
multi-primary multi-network, measured with [`bin/retoken`](../../bin/retoken).

## How it was found

The 1.30.3 write-up got as far as "listeners are never unregistered" from a
goroutine diff. That was correct but incomplete, and pprof could not close the
gap: a heap profile tells you *what* is retained, never *who* retains it. Two
techniques did:

### Counters, not profiles

Temporary `XXXX` log lines with atomic counters around every lifecycle edge —
listener add/remove, dependency register/unregister, collection creation, debug
registry size, cluster GC finalisers — turn "the heap grows" into a table where
exactly one column fails to plateau. A counter that only ever goes up names the
mechanism; a heap profile only names the allocation site.

### Queue lifetimes name the collection

The decisive probe was six lines in `pkg/queue/instance.go`:

```go
func (q *queueImpl) Run(stop <-chan struct{}) {
	log.Infof("XXXX [QUEUE] (+) queue started id=%q liveQueues=%d", q.id, liveQueues.Add(1))
	defer func() {
		log.Infof("XXXX [QUEUE] (-) queue stopped id=%q liveQueues=%d", q.id, liveQueues.Add(-1))
		...
```

Every krt collection with a transformation runs a queue named after the
collection. Diffing starts against stops per rotation produced a one-line
answer:

```
queues started but not stopped in one rotation window:
  +1 -0  ambient/GlobalNodeLocalityWithCluster
```

A krt collection whose queue never exits is a collection whose stop channel
never closes, which is a collection that will keep its whole parent chain alive.
This is a generic invariant worth keeping: **in a healthy multicluster istiod,
every queue started during a cluster rebuild must stop during the same
rebuild.**

## Cause 1: `Fetch` dependencies were registered one-way

`collectionDependencyTracker.registerDependency` installed a handler on the
dependency and threw the registration away — the `register` callback was even
typed to return a `Syncer` rather than a `HandlerRegistration`, so the caller
*could not* have kept it. `UnregisterHandler()` existed but nothing in
production called it.

The listener lives in the **dependency's** handler set and its closure captures
the **registrant**. When the registrant is per-cluster and the dependency is a
process-lifetime global (`MeshConfig`, `ambient/RemoteSystemNamespaceNetworks`,
`ambient/AuthzDerivedPolicies`, `informer/Namespaces`, …), the global keeps the
dead per-cluster collection alive: 2 goroutines and a 1024-slot ring buffer per
listener, ~27 of them per rotation.

**Fix.** `registerDependency` now takes `func(erasedEventHandler) HandlerRegistration`.
`manyCollection` records every registration it makes — both `Fetch` dependencies
and the primary input handler — and tears them down from `runQueue`'s `defer`:

```go
func (h *manyCollection[I, O]) runQueue() {
	defer h.unregisterDependencies()
```

`runQueue` returns exactly when the collection's stop channel closes (all three
exit paths go through `WaitUntilSynced(h.stop)` or `queue.Run(h.stop)`, and both
only return early on stop), so this costs no extra goroutine and needs no
separate watcher.

### The mirror-image leak the fix introduced

Holding registrations flips the retention arrow: a **long-lived** collection that
fetches a **per-cluster** one (`ambient/RemoteSystemNamespaceNetworks` →
`informer/Namespaces[cluster]`, once per rotation) would now hold a registration
whose `remove` closure captures the dead informer.

So registrations know when their collection has stopped
(`handlerRegistration.stop`, `informerHandlerRegistration.stop`,
`registrationStopped()`), and `trackDependencyRegistration` drops dead ones
before appending. A stopped registration can never fire again, so dropping it
without calling `UnregisterHandler` is safe.

## Cause 2: `krt.DebugHandler` pinned every collection ever created

`maybeRegisterCollectionForDebugging` appended to a slice with no removal API,
and `pilot/pkg/bootstrap` enables the debugger unconditionally in production.
Each entry holds a `dump` method value bound to the collection, which
transitively pins its indexes, its `kclient` and the informer cache. The counter
went 1 → 836 in 24 rotations.

**Fix.** `DebugCollection` carries the collection's stop channel; entries for
stopped collections are pruned on every registration and before marshalling. All
eight constructors now pass `o.stop`.

## Cause 3: one collection was built with the wrong stop channel

`GlobalNodesCollection` builds an inner per-cluster collection inside the outer
transformation, and reused the **outer** options for it:

```go
nc := krt.NewCollection(col, func(...) {...},
	append(opts, krt.WithMetadata(...))...)   // opts = the process-lifetime options
```

`opts` carries the ambient controller's name *and* its stop channel. The
resulting collection therefore never stopped: its queue kept running, it kept
its handler registered on the dead per-cluster nodes collection, and through
`manyCollection.parent` it kept the per-cluster `informer/Nodes` → `kclient` →
`kube.Client` → the client's whole informer factory reachable. That is where the
`PartialObjectMetadata` (the CRD watcher's metadata cache) and the Pod/Service/
EndpointSlice caches were being retained — ~1.4 MB per rotation.

The neighbouring collections in `multicluster.go` already state the rule
explicitly:

> N.B we're not using the `opts.WithXXX` pattern here since we want to be very
> obvious about which stop is being used to shutdown the collection (it should
> always be the cluster stop, NEVER the top-level stop associated with the
> ambient controller)

`GlobalNodesCollection` could not follow it because it only receives a
`krt.Collection`, not the `*multicluster.Cluster`. It now takes the controller
and resolves the cluster through krt itself:

```go
c := krt.FetchOne(ctx, ctrl.Clusters(), krt.FilterKey(id.String()))
if c == nil {
	return nil
}
innerOpts := append(slices.Clone(opts),
	krt.WithName(fmt.Sprintf("ambient/NodeLocalityWithCluster[%s]", id)),
	krt.WithStop((*c).GetStop()),
	...
```

Fetching (rather than closing over a lookup) also makes the outer collection
recompute when the cluster is replaced, which is exactly the desired behaviour.

Note this bug is visible in the 1.30.3 goroutine diff too — `+1
krt.manyCollection[…Node].runQueue` and `+1 queue.(*queueImpl).Run` per
rotation — it just was not attributed at the time.

## Results

Per-rotation counters, 17 rotations at 10 s intervals, all three fixes in:

```
rot goroutines  heapMB  colls  liveDep  liveLis  liveQ
  1       1630      50    449      174      197     96
  5       1617      71    593      174      229     96
 10       1617      75    775      174      269     96
 16       1617      94    991      174      317     96
```

`goroutines`, `liveDep` and `liveQ` are flat. `liveLis` is a counting artifact:
listeners that exit through their stop channel do not go through
`handlerSet.remove`, so they were never subtracted (fixed in the instrumentation
afterwards); they belong to collections that are themselves garbage.

Retained heap, 20 rotations, both snapshots taken with `?gc=1` and diffed with
`pprof -base`: +23.9 MB total, of which 10.6 MB is the gRPC `sizedBufferPool`
(pooled, not retained) and only **2.9 MB is `ObjectMeta.Unmarshal`**, i.e.
0.14 MB per rotation against 1.4 MB before.

## Measurement gotchas

- **Rotate no faster than istiod can process.** At `INTERVAL=3` istiod saw only
  3 of 20 rotations — the secret controller coalesces — and every derived
  per-rotation figure is then meaningless. `bin/retoken` warns when the observed
  `remote_cluster_secret_events_total` delta does not match the requested
  iterations. 10 s is comfortable for this lab.
- **`heap_inuse` is not retention.** It swings 45 → 95 MB within a run and drops
  back. Only `/debug/pprof/heap?gc=1` before and after, diffed with
  `pprof -base`, distinguishes a leak from GC slack.
- **Let the binary land.** Tilt live-syncs `out/linux_arm64/pilot-discovery` and
  `entr` restarts istiod; occasionally it hits `entr: exec …: Text file busy` and
  crash-loops once before recovering. Always confirm `RESTARTS` advanced *before*
  the run, never during, and take the baseline after the restart.
- **A restart mid-run inverts the result.** One early run reported "-6.2
  goroutines per rotation" purely because istiod restarted in the middle.

## Changes

Functional:

| File | Change |
|---|---|
| `pkg/kube/krt/internal.go` | `registerDependency` returns `HandlerRegistration`; `isStopped` / `registrationStopped` helpers |
| `pkg/kube/krt/collection.go` | track and unregister dependency + primary registrations on stop; prune registrations on stopped collections |
| `pkg/kube/krt/fetch.go`, `testing.go` | follow the new signature |
| `pkg/kube/krt/processor.go`, `informer.go` | registrations carry the collection stop channel |
| `pkg/kube/krt/debug.go` (+ 8 constructors) | prune stopped collections from the debug registry |
| `pilot/pkg/serviceregistry/ambient/nodes.go`, `multicluster.go` | per-cluster node locality collection uses the cluster stop and a per-cluster name |

Temporary `XXXX` instrumentation (to be removed before upstreaming):
`pkg/queue/instance.go`, `pkg/kube/informerfactory/factory.go`,
`pkg/kube/multicluster/{cluster,clusterstore,component,secretcontroller}.go`, and
the counters/logs in `pkg/kube/krt/{collection,debug,processor,nestedjoinmerge}.go`.

## Retest against upstream (2026-08-17)

Upstream picked up two of the three causes after the issues were reported:

| Cause | Upstream PR | Merge commit | Status |
|---|---|---|---|
| 1. `Fetch` dependencies registered one-way | [#61253](https://github.com/istio/istio/pull/61253) | `1a22e33fce` | merged to `master` |
| 2. `krt.DebugHandler` append-only | — | — | **not fixed** |
| 3. wrong stop channel in `GlobalNodeLocalityWithCluster` | [#61255](https://github.com/istio/istio/pull/61255) | `8dc789c5cf` | merged to `master` |

Upstream fixes cause 1 differently: `dependencyState` gained
`collectionDependencyHandlers map[collectionUID]HandlerRegistration`, and
`manyCollection.runQueue` unregisters every entry (plus the primary registration)
when the collection stops. It does **not** prune entries whose *dependency* has
stopped, which is the mirror-image case: a long-lived collection that `Fetch`es a
per-cluster collection keeps the registration — and therefore the dead cluster's
client and informer caches — forever.

Measured on `1.31.0-alpha.2` + both upstream cherry-picks, 20 rotations at 10 s,
heap sampled with `?gc=1`, diff of sample 0 vs sample 4:

| Build | goroutines / rotation | retained over 20 rotations | per rotation |
|---|---|---|---|
| upstream fixes only | −0.1 | 55.0 MB | 2.75 MB |
| \+ debug registry pruning | −0.1 | 44.3 MB | 2.21 MB |
| \+ stale dependency registration pruning | −0.1 | 16.7 MB | 0.83 MB |

The goroutine leak is fully fixed upstream (was +30.8 per rotation). What upstream
still retains, and what each remaining fix recovers:

- Ring buffers (`buffer.NewTypedRingGrowing`, 1024 slots per listener): 14.25 MB
  over 20 rotations with upstream only, 1.56 MB with the debug registry pruning —
  the debug registry was holding dead collections whose listeners had already been
  unregistered and whose goroutines had already exited.
- `PartialObjectMetadata` (94.6% of the `ObjectMeta.Unmarshal` growth): 18.5 MB
  with upstream only, 16.1 MB with the debug fix, **negative** (freed) once stale
  dependency registrations are pruned — these are the discarded clusters' metadata
  informer caches, pinned by registrations held in `collectionDependencyHandlers`.

With both remaining fixes the diff is dominated by the gRPC `sizedBufferPool`
(3.5 MB) and TLS/HTTP2 buffers, i.e. pool churn rather than retention.

Branches (each rebased on the upstream fixes, no `XXXX` instrumentation):

| Branch | Commit |
|---|---|
| `fix/krt-debug-registry-leak` | `krt: prune stopped collections from the debug registry` |
| `fix/krt-stale-dependency-registrations` | `krt: drop dependency registrations on stopped collections` |

## What is still there

- ~0.8 MB per rotation of heap diff remains, almost entirely gRPC buffer pools and
  TLS/HTTP2 buffers. Not retention; not chased further.
- **Diagnosis 5 of the original write-up** (orphaned `pendingSwap` when rotations
  outpace sync) is untouched. It is a real hazard at short intervals but was not
  what leaked here.
- The two incidental bugs (`/debug/krtz` HTTP 500, `istiod_remote_cluster_sync_status`
  stuck on `closed`) are still open.
