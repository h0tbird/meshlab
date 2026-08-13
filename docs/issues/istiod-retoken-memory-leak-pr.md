# Draft PR: fix the istiod leak on remote-secret updates

Working notes for opening this upstream. Target `istio/istio`, base `master`;
the work currently sits on the `1.31.0-alpha.2` tag in `/workspaces/istio` and
still carries the temporary `XXXX` instrumentation.

## Before opening

- [ ] Strip all `XXXX` logging and the atomic counters that back it
      (`pkg/queue/instance.go`, `pkg/kube/informerfactory/factory.go`,
      `pkg/kube/multicluster/{cluster,clusterstore,component,secretcontroller}.go`,
      and the log lines in `pkg/kube/krt/{collection,debug,processor,nestedjoinmerge}.go`).
      After that only 7 files change.
- [ ] Rebase onto `master` and re-run the lab measurement on that base.
- [ ] Add krt unit tests: a collection that `Fetch`es a longer-lived one must
      leave no handler behind after its stop channel closes, and `DebugHandler`
      must not retain stopped collections.
- [ ] `releasenotes/notes/multicluster-remote-secret-leak.yaml` is already in the
      tree; confirm the issue reference.
- [ ] Consider splitting into three PRs — krt handler lifecycle, debug registry
      pruning, ambient nodes stop channel. The third is a one-file fix that could
      be cherry-picked to release branches on its own.

## Title

```
fix: stop leaking collections, handlers and informer caches on remote cluster rebuild
```

## Description

```markdown
## What this fixes

Any change to an `istio/multiCluster` remote secret makes istiod rebuild the
whole remote cluster stack (make-before-break). The teardown half is incomplete,
so a service account token rotator is enough to grow istiod without bound: in a
two-cluster ambient lab each rotation permanently cost **~30 goroutines and
several MB of live heap**, with no plateau and no recovery.

Related: #60033.

There are three independent causes.

### 1. krt `Fetch` dependencies were never unregistered

`collectionDependencyTracker.registerDependency` installed an event handler on
the dependency collection and discarded the result — the `register` callback was
typed to return a `Syncer`, so the registration could not be kept even in
principle. `UnregisterHandler()` was never called from production code.

The handler lives in the **dependency's** handler set while its closure captures
the **registrant**. That is harmless when both have the same lifetime, and a
leak when a per-cluster collection fetches a process-lifetime global — which is
exactly what ambient multicluster does (`PodWorkloads[cluster]`,
`Waypoints[cluster]`, `ServiceServiceInfos[cluster]` and
`EndpointSliceWorkloads[cluster]` fetch `MeshConfig`,
`ambient/RemoteSystemNamespaceNetworks`, `ambient/AuthzDerivedPolicies`,
`GatewayClasses`, …). Each leaked handler is two goroutines plus a 1024-slot
ring buffer, and it keeps the dead per-cluster collection reachable. ~27 of them
per rebuild.

`registerDependency` now hands back a `HandlerRegistration`. `manyCollection`
records every registration it makes — dependencies and its primary input — and
unregisters them from `runQueue`'s `defer`, which runs exactly when the
collection's stop channel closes.

The reverse direction needs care: a long-lived collection also fetches
short-lived ones (`ambient/RemoteSystemNamespaceNetworks` re-subscribes to each
rebuild's new `informer/Namespaces[cluster]`), and holding those registrations
would keep the dead informer alive through the `remove` closure. Registrations
therefore know whether their collection has stopped, and stopped ones are
dropped from the tracking slice instead of being unregistered — a stopped
handler can never fire again.

### 2. `krt.DebugHandler` was an append-only registry

`maybeRegisterCollectionForDebugging` appended to a slice with no removal path,
and `pilot/pkg/bootstrap` installs the debugger unconditionally, so this is on in
production. Every entry holds a `dump` method value bound to the collection,
pinning its indexes, its `kclient` and the informer cache behind it. In a 24
rotation run the registry grew from 1 to 836 entries.

`DebugCollection` now carries the collection's stop channel and stopped entries
are pruned on registration and before marshalling.

### 3. `ambient/GlobalNodeLocalityWithCluster` used the wrong stop channel

`GlobalNodesCollection` builds a per-cluster inner collection inside the outer
transformation, and passed the **outer** options — including the ambient
controller's process-lifetime stop channel — down to it. That collection
therefore never stopped: its queue kept running and, through
`manyCollection.parent`, it kept the per-cluster nodes informer, its `kclient`,
the cluster's `kube.Client` and that client's entire informer factory reachable.
This is where the retained megabytes were: the CRD watcher's
`PartialObjectMetadata` cache plus the Pod/Service/EndpointSlice caches of every
discarded cluster.

The surrounding code in `pilot/pkg/serviceregistry/ambient/multicluster.go`
already documents the rule ("it should always be the cluster stop, NEVER the
top-level stop associated with the ambient controller"); this collection could
not follow it because it only received a `krt.Collection`, not the
`*multicluster.Cluster`. It now takes the `*multicluster.Controller` and
resolves the cluster with `krt.FetchOne(ctx, ctrl.Clusters(), …)`, which also
makes the outer collection recompute when a cluster is replaced. The inner
collection gets `krt.WithStop(cluster.GetStop())` and a `[clusterID]` suffixed
name.

## Testing

Two-cluster kind lab, ambient multi-primary multi-network, 8 workloads,
rotating the remote reader service account token every 10s and doing nothing
else. Measurements taken from `/debug/pprof/heap?gc=1` diffed with `pprof -base`
and from the goroutine profile.

| metric | before | after |
|---|---|---|
| goroutines per rotation | +30.8 | ~0 (flat over 17 rotations) |
| live krt dependency handlers | +27 per rotation | flat |
| running krt queues | +1 per rotation | flat |
| debug registry entries | 1 → 836 in 24 rotations | pruned |
| retained informer cache, post-GC | ~1.4 MB per rotation | ~0.14 MB per rotation |

Existing tests pass: `go test ./pkg/kube/... ./pkg/queue/... ./pilot/pkg/serviceregistry/...`.

## Release notes

`releasenotes/notes/multicluster-remote-secret-leak.yaml`.
```

## Files changed (after the instrumentation is stripped)

| File | Change |
|---|---|
| `pkg/kube/krt/internal.go` | `registerDependency` returns `HandlerRegistration`; `isStopped`/`registrationStopped` helpers |
| `pkg/kube/krt/collection.go` | track registrations, unregister on stop, prune stopped ones |
| `pkg/kube/krt/fetch.go` | follow the new `registerDependency` signature |
| `pkg/kube/krt/testing.go` | same, for `TestingDummyContext` |
| `pkg/kube/krt/processor.go` | `handlerRegistration` knows its collection's stop channel |
| `pkg/kube/krt/informer.go` | same for `informerHandlerRegistration` |
| `pkg/kube/krt/debug.go` (+ `index.go`, `informer.go`, `map.go`, `mergejoin.go`, `nestedjoinmerge.go`, `singleton.go`, `static.go`) | prune stopped collections from the debug registry; constructors pass `stop` |
| `pilot/pkg/serviceregistry/ambient/nodes.go` | inner collection uses the cluster stop and a per-cluster name |
| `pilot/pkg/serviceregistry/ambient/multicluster.go` | pass the multicluster controller |

## Anticipated review questions

- **Why unregister from `runQueue` instead of a dedicated goroutine?**
  All exit paths of `runQueue` are gated on `h.stop`
  (`WaitUntilSynced(h.stop)`, `queue.Run(h.stop)`), so it returns exactly when
  the collection stops. No extra goroutine, no extra channel.
- **Why drop rather than unregister handlers on stopped collections?**
  `UnregisterHandler` on a stopped collection would take its lock and mutate its
  handler set for no benefit; a stopped collection never dispatches again and its
  entire handler set is garbage. Dropping the reference is what actually breaks
  the retention.
- **Does the debug registry pruning change `/debug/krt` output?**
  Only by removing collections that no longer exist. (Note `/debug/krtz` is
  currently a 500 for an unrelated marshalling issue — a dumped collection
  contains a `chan struct{}` — worth a separate PR.)
- **Is `GlobalNodesCollection`'s new signature a problem?**
  It is an exported function in `pilot/`, not a public API surface; the only
  caller is ambient's multicluster wiring.
