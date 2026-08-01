# The 1.29 re-tokening heap leak bisects to the deadlock fix (#59876)

> Which commit made `istiod` leak memory on remote-secret re-tokening in the
> 1.29 line?
>
> **`c55428035e4f`**, *"Fix deadlock in secret controller during remote cluster
> update (Fixes #59875) (#59876)"*, first shipped in **1.29.3**. It is a
> release-branch-only commit; it was never merged to `master`.

## TL;DR

| | |
|---|---|
| First bad commit | [`c55428035e4f`](https://github.com/istio/istio/commit/c55428035e4fa2ef0871842a7ce57a7a8cc0e86e) (`release-1.29` only) |
| First affected release | 1.29.3 |
| Cost per rotation | ~2.1–2.3 MB of live heap, **0 goroutines** |
| Shape | Retention leak: the goroutines of the old remote-cluster stack exit, their heap is never released |
| 1.29.3 – 1.29.4 | `panic: close of closed channel` instead — the process dies before it can leak |
| 1.29.5 – 1.29.6 | Panic fixed by `9d9ac3fd8601` (#60522); the leak remains and is measurable |
| Fix direction | **Not** a revert. The parent does not leak only because its secret controller deadlocks on the first rotation |
| Range bisected | `1.29.0` → `ab36613b3ef2` (1.29.3), 9 commits tested, no skips |

## Lab facts

| Item | Value |
|---|---|
| istiod | built per commit from `release-1.29`, chart pinned `1.29.0`, deployment `istiod-1-29-0` |
| Clusters | `kind-pasta-1` (SRC, holds the remote secret), `kind-pasta-2` (DST) |
| Remote secret | `istio-remote-secret-pasta-2` in `istio-system` on `pasta-1` |
| Gateway API | `v1.4.1` |
| Carried on every commit | `9d9ac3fd8601` (`multicluster: make kubeController.Close idempotent with sync.Once`, #60522), without which every commit from `c55428035e4f` to 1.29.4 panics under rotation |
| Measurement | 40 rotations, 5 s apart, sampled every 10 |

## How the commit was found

[`bin/retoken`](../../bin/retoken) in `bisect` mode is a pass/fail probe for one
istio commit: it builds `pilot-discovery`, waits for Tilt to live-sync that exact
binary into istiod, idles until the goroutine count is flat, rotates the remote
secret 40 times, and turns the resulting slope into a `git bisect` exit code.

```sh
cd /workspaces/istio
git bisect start ab36613b3ef2 1.29.0   # bad, good
git bisect run retoken bisect
```

Two things had to be fixed before the bisect could tell the truth.

### The fixup has to survive a fresh checkout

`git bisect` checks out each commit immediately before the probe runs, and
`git apply --3way` consults the index — it reported `does not match index` for a
file checked out moments earlier and the probe skipped a perfectly good commit.
The blob was identical at the skipped commit, at the fixup's parent and at
`c55428035e4f`, so this was never a content conflict. `apply_fixups` now
refreshes the stat cache first and falls back to a plain `git apply`, which needs
no index at all.

### The verdict has to look at the heap

The first bisect attempt judged commits on goroutines alone and called
**everything** clean, including the known-bad `1.29.6` end:

| commit | release | goroutines/rot | heap MB/rot | old verdict |
|---|---|---|---|---|
| `ab36613b3ef2` | 1.29.3 | −0.03 | +2.364 | clean |
| `0c6f50366ac1` | 1.29.5 | −0.03 | +2.626 | clean |
| `7aa11a61d78e` | 1.29.6 | −0.05 | +2.224 | clean |
| `3e122e2b814e` | 1.29.6 | −0.05 | +2.658 | clean |

On the 1.29 line the discarded remote-cluster stack lets its goroutines exit but
keeps its heap, so the leak is invisible to a goroutine-only predicate — the
opposite of the 1.30.3 leak documented in
[`istiod-retoken-memory-leak.md`](istiod-retoken-memory-leak.md), where 30
goroutines per rotation are the loudest signal. `retoken` grew a `HEAP_THRESHOLD`
(default 1 MB per rotation) and now condemns a commit when *either* dimension
crosses. That log of four bogus `clean` verdicts was discarded and the bisect
restarted from scratch.

The threshold separates the ends of the range with room to spare: `1.29.0`
measures **−0.27** MB per rotation, every commit from `c55428035e4f` on sits
above **+2.0**.

## Evidence

### The bisect

Nine commits, no skips, every run recorded in `/tmp/retoken-results.csv`:

| commit | release | goroutines/rot | heap MB/rot | verdict |
|---|---|---|---|---|
| `2300e2458ab7` | 1.29.0 | −2.55 | −0.271 | clean |
| `6ba4dbaffe3b` | 1.29.2 | −2.58 | −0.103 | clean |
| `aa6165711cc9` | 1.29.2 | −2.58 | −0.233 | clean |
| `27a4a329f9e1` | 1.29.2 | −2.62 | −0.060 | clean |
| `20c85437319b` | 1.29.3 | −2.60 | −0.271 | clean |
| `10ae2d6caadf` | 1.29.3 | −2.58 | −0.107 | clean ← parent |
| **`c55428035e4f`** | **1.29.3** | **−0.03** | **+2.299** | **leak** |
| `a0b33925d1aa` | 1.29.3 | −0.05 | +2.197 | leak |
| `ab36613b3ef2` | 1.29.3 | 0.00 | +2.128 | leak |

`10ae2d6caadf` is the direct parent of `c55428035e4f`, so the transition is
exact, not interpolated. The −2.5 goroutines per rotation on the clean side is
not a trend: it is the one-off ~100-goroutine drop of the first rotation divided
by 40 (see below).

### It is retention, not goroutines

40 rotations against `c55428035e4f` with profiling on: heap **52.4 → 136.2 MB**
(+2.09 MB per rotation) while the goroutine profile moved by **−2**. The old
remote-cluster goroutines do exit; only their memory stays.

`pprof -diff_base` between the first and last sample, +39 MB of live bytes:

| site | share |
|---|---|
| `v1.(*ObjectMeta).Unmarshal` ← `PartialObjectMetadata.Unmarshal` | **90%** |
| `buffer.NewTypedRingGrowing[interface{}]` | 4% |
| `EndpointSlice` / `Secret` / `ConfigMap` / `Service` / `Pod` unmarshal | ~1.4% each |

Every one of those allocations is on the same stack:

```
v1.(*ObjectMeta).Unmarshal
v1.(*PartialObjectMetadata).Unmarshal
protobuf.unmarshalToObject
protobuf.(*Serializer).Decode
runtime.WithoutVersionDecoder.Decode
rest/watch.(*Decoder).Decode
watch.(*StreamWatcher).receive
```

— decoded watch events sitting in informer caches. By live object count the
retained structures are the client stack itself:

| Δ live objects over 40 rotations | site |
|---|---|
| +17431 | `informerfactory.(*informerFactory).InformerFor` |
| +6918 | `client-go/rest.NewRESTClient` |
| +5461 | `pilot/pkg/credentials/kube.NewMulticluster.func1` |
| +2521 | `cache.(*storeIndex).addKeyToIndex` |
| +2185 | `cache.NewReflectorWithOptions` |

So each re-tokening builds a complete new remote-cluster client stack — REST
client, reflectors, informers, caches — and the previous one stays reachable
after its goroutines have stopped. `Client.Shutdown()` stops the goroutines;
nothing drops the objects.

## Diagnosis

### What the commit changed

`c55428035e4f` adds a second teardown call to `addSecret`:

```go
// stop previous remote cluster
prev.Stop()
for _, h := range c.handlers {   // new in #59876
    h.clusterClosing(prev.ID)
}
prev.Client.Shutdown() // Shutdown all of the informers so that the goroutines won't leak
```

and the `clusterClosing` it dispatches to:

```go
func (m *Component[T]) clusterClosing(cluster cluster.ID) {
	m.mu.RLock()
	old, f := m.clusters[cluster]
	m.mu.RUnlock()
	if f {
		old.Close()
	}
}
```

`Component.clusterUpdated` already closed the old component, *after* building the
replacement:

```go
func (m *Component[T]) clusterUpdated(cluster *Cluster) ComponentConstraint {
	// Build outside of the lock, in case its slow
	comp := m.constructor(cluster)
	old, f := m.clusters[cluster.ID]
	m.mu.Lock()
	m.clusters[cluster.ID] = comp
	m.mu.Unlock()
	// Close outside of the lock, in case its slow
	if f {
		old.Close()                  // now the second Close
	}
	return comp
}
```

So `Close()` runs twice on the same object. For `kubeController` that means
`close(k.stop)` twice — the `panic: close of closed channel` that makes 1.29.3
and 1.29.4 crash under rotation. `9d9ac3fd8601` (#60522, in 1.29.5) wraps `Close`
in a `sync.Once`, which stops the panic and leaves the ordering change standing:
teardown — `UnRegisterHandlersForCluster`, both `DeleteRegistry` calls and
`Controller.Cleanup()` — now happens *before* `prev.Client.Shutdown()` and before
the replacement is constructed, where it used to happen after both.

### The parent does not leak because it deadlocks

This is the part that matters for any fix. Profiling the parent commit
`10ae2d6caadf` over 40 rotations gives a flat heap — 40.4 MB → 39.2 MB, −0.03 MB
per rotation — and one goroutine parked forever:

```
1   runtime.gopark
    sync.(*WaitGroup).Wait
    informerfactory.(*informerFactory).Shutdown
    kube.(*client).Shutdown
    multicluster.(*Controller).addSecret
    multicluster.(*Controller).processItem
    controllers.Queue.processNextItem
    controllers.Queue.Run.func1
```

That is the *only* worker of the `multicluster secret` queue. It is absent in the
sample taken before the first rotation and present in every sample after it:

| sample | rotations | goroutines | heap | worker parked in `addSecret` |
|---|---|---|---|---|
| 0 | 0 | 912 | 40.4 MB | no |
| 1 | 10 | 926 | 49.4 MB | yes |
| 2 | 20 | 927 | 52.2 MB | yes |
| 3 | 30 | 926 | 39.9 MB | yes |
| 4 | 40 | 926 | 39.2 MB | yes |

The **first** rotation gets as far as `prev.Client.Shutdown()` and blocks there
for the rest of the process's life. Rotations 2 to 40 are enqueued and never
reconciled. The heap is flat because nothing is being rebuilt — this is the
deadlock of [#59875](https://github.com/istio/istio/issues/59875) caught in the
act, not a healthy control plane.

The metric does not give this away. `remote_cluster_secret_events_total` is
incremented in the secret informer's event handler, *before* `queue.AddObject` —
so `retoken`'s guard (abort unless the update counter advances by at least half
the iterations) only proves istiod **observed** every rotation, not that it
processed any of them. It passed on every clean run.

Diffing the goroutine profiles across the transition makes the missing work
visible. The leaking commit carries **+101** goroutines over the parent, and they
are a live remote-cluster stack:

| Δ vs parent | frames |
|---|---|
| +9 | `http2.(*clientStream).doRequest` / `transportResponseBody.Read` — open watch connections |
| +5 | `informerfactory.(*informerFactory).startOne.func1` |
| +4 | `informerfactory.(*informerFactory).Start.func1` |
| +2 | `krt.processorListener[*MeshConfig].run` / `.pop` |
| +1 each | `multicluster.(*Cluster).Run.func2`, `kclient.(*crdWatcher).Run`, `controllers.Queue.Run`, `namespace.newDiscoveryNamespacesFilter.func2` |
| −1 each | `addSecret` / `processItem` / `client.Shutdown` / `informerFactory.Shutdown` — the deadlocked worker, present only on the parent |

The whole-process numbers say the same thing. Across the bisect, goroutines
settle at ~927 on every clean commit and at ~1028 on every leaking one, and
neither drifts with rotations:

| sample | `2300e2458ab7` (1.29.0) | `10ae2d6caadf` (parent) | `a0b33925d1aa` (leak) |
|---|---|---|---|
| 0 | 1027 | 1030 | 1030 |
| 10 | 925 | 927 | 1028 |
| 20 | 924 | 927 | 1028 |
| 30 | 925 | 927 | 1028 |
| 40 | 925 | 927 | 1028 |

The clean commits converge on ~927 goroutines and then stop moving, whether they
reach it from above (1030 in the bisect runs, a ~100-goroutine loss on the first
rotation) or from below (912 in the profiled rerun, which started from a colder
process). The remote-cluster stack is torn down once and never rebuilt, and
istiod keeps serving the state it already had.

Read together: `#59876` genuinely fixed the teardown-without-rebuild deadlock,
and by making the rebuild path run it exposed the fact that the rebuild path
never frees the old stack. **Reverting it trades a memory leak for a silently
dead remote cluster.**

## Reproducing

```sh
# one measurement of the current istio checkout, with profiles
cd /workspaces/meshlab
PROFILE=true bin/retoken bisect

# the profiles it leaves behind
go tool pprof -inuse_space -top -diff_base <outdir>/heap.sample-0.pb.gz <outdir>/heap.sample-4.pb.gz
go tool pprof -top -diff_base <outdir>/goroutine.sample-0.pb.gz <outdir>/goroutine.sample-4.pb.gz
```

`bisect` mode defaults to `PROFILE=false` to keep each bisect step cheap, so the
profiles above have to be asked for explicitly.

## Open questions

- Allocation profiles show *what* is retained and *that* it is retained, but not
  by which pointer. Naming the exact edge means reading who still references the
  old `Component` / `Cluster` after `clusterClosing`, or taking a heap graph.
- Whether the same ordering exists on `master`. `master` has no `clusterClosing`
  at all — it solved the race in `cdc5dca45d` (*"fix data race in pending
  swap"*, #59070) — so the 1.30.3 leak documented next door has a different
  proximate cause even though the symptom rhymes.

## Upstream context

- [#59875](https://github.com/istio/istio/issues/59875) — *"[release-1.29]
  Deadlock in secret controller during remote cluster update in 1.29 (observed in
  1.27-1.29 multiversion tests)"*, closed.
- [#59876](https://github.com/istio/istio/pull/59876) — the fix, merged into
  `release-1.29` only.
- `9d9ac3fd8601` / [#60522](https://github.com/istio/istio/pull/60522) —
  *"multicluster: make kubeController.Close idempotent with sync.Once"*, in
  1.29.5, which turns the resulting panic into this leak.
- [`istiod-retoken-memory-leak.md`](istiod-retoken-memory-leak.md) — the 1.30.3
  leak: same trigger, but ~2.4 MB **and 30 goroutines** per rotation, caused by
  KRT listeners and `DebugHandler` retention.
