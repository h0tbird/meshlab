# Startup timing: Kindnet and cloud-provider-kind

Experiment date: 2026-09-07.

## Outcome and scope

Two independent startup waits were identified. Kindnet can reconcile an empty
node informer cache and then wait 10 seconds before writing its CNI configuration.
cloud-provider-kind can scan before clusters exist and wait 30 seconds before
discovering them again. Removing only one wait does not necessarily shorten
`meshlab create`, because the other remains on the critical path.

With both addressed, Argo CD setup consistently fell from 24 seconds to 14 seconds.
Full creation times were more variable: 90/88 seconds with stock Kindnet versus
71/84 seconds with the experimental patch. These are small, warm-cache samples,
not a statistically established end-to-end speedup.

The changes retained in meshlab are:

- Argo CD's `controller.sync.wave.delay.seconds` Helm value set to `"1"`.
- Docker network creation separated from cloud-provider-kind startup.
- cloud-provider-kind started after cluster creation, with Kubernetes setup
  depending on successful controller startup.

The Kindnet patch is **experimental and not installed by these changes**. The lab
was rebuilt with stock images after testing. An upstream fix is preferable to a
permanent override of kind's internal bootstrap manifest.

## Environment and method

The lab used three single-node clusters (`mnger-1`, `pasta-1`, `pasta-2`) in an
ARM64 Linux devcontainer. Relevant versions were:

| Component | Version |
| --- | --- |
| Kind node | `kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5` |
| Kindnet | `docker.io/kindest/kindnetd:v20260820-69b56db7` |
| Kindnet source | kubernetes-sigs/kind revision `69b56db7` |
| cloud-provider-kind | `0.11.1` |
| Argo CD Helm chart | `10.7.1` (Argo CD `v3.5.2`) |
| Argo Workflows Helm chart | `2.0.3` |
| Kiali operator Helm chart | `2.31.0` |
| Istio | `1.31.0` |

Full runs used `meshlab delete` followed by `meshlab create`. Delete preserves the
Zot image-cache volume, so these measurements do not include a cold image cache.
Logs were saved outside `.tmp`, which delete removes. `pipefail` was enabled so
log filtering could not hide a failed create command. Workflow timings came from
the bootstrap Workflow in namespace `argocd`, not `argowf`.

The previously committed Kiali operator probe tuning was present throughout.
An earlier kubelet status-frequency experiment did not improve readiness and was
reverted before the tests described here.

## Kindnet startup race and patch

The [pinned Kindnet main loop](https://github.com/kubernetes-sigs/kind/blob/69b56db7/images/kindnetd/cmd/kindnetd/main.go)
starts the informer factory and immediately lists nodes through its cached
lister. Before the initial LIST finishes, an empty cache can return an empty
node list without an error. Reconciliation then does no work, and the loop waits
for its next 10-second tick. During reconciliation of the local node, Kindnet
writes `/etc/cni/net.d/10-kindnet.conflist`; until then pod networking is not ready.

The patch changes only `images/kindnetd/cmd/kindnetd/main.go`. Add this import:

```go
"k8s.io/client-go/tools/cache"
```

Immediately after `informersFactory.Start(ctx.Done())`, wait for the node cache
before constructing the ticker and entering the existing loop:

```go
informersFactory.Start(ctx.Done())
if !cache.WaitForCacheSync(ctx.Done(), nodeInformer.Informer().HasSynced) {
	return
}
ticker := time.NewTicker(10 * time.Second)
defer ticker.Stop()
```

This uses the existing cancellation context and leaves steady-state polling,
route reconciliation, and CNI generation unchanged. It waits only for the node
cache, not for all network-policy initialization to complete. Cache sync also
does not guarantee a local node has already received its PodCIDR; the existing
reconciliation loop remains responsible for subsequent updates.

### Isolated A/B test

Disposable single-node clusters were created with default CNI disabled. The
stock CNI manifest from the pinned node image was applied with the appropriate
image, test PodSubnet, and control-plane endpoint. Images were imported before
measurement. Both test clusters were deleted afterward.

| Event (UTC) | Stock | Patched |
| --- | --- | --- |
| Connected to API | 15:40:27.815593 | 15:40:53.317620 |
| CNI file written | 15:40:37.822403548 | 15:40:53.425193167 |
| API connection to CNI write | 10.007s | 0.108s |
| Node Ready timestamp | 15:40:37 | 15:40:53 |

`go test ./cmd/kindnetd` succeeded but reported **no test files**; compilation and
the live A/B experiment, not automated regression coverage, validate this probe.
Before proposing the change upstream, add a regression test for delayed informer
sync and cancellation, and test multi-node, dual-stack, and network-policy startup.

## cloud-provider-kind discovery wait

The [v0.11.1 discovery loop](https://github.com/kubernetes-sigs/cloud-provider-kind/blob/v0.11.1/pkg/controller/controller.go)
scans immediately and then waits `30 * time.Second` between scans. Previously,
meshlab started it before creating the clusters. In one measured run:

- Controller process started at 15:42:24.
- Argo CD pods were Ready by 15:42:47.
- First manager-cluster discovery occurred at 15:42:54.
- Argo CD and Argo Workflows LoadBalancer addresses were assigned at 15:42:54.
- Bootstrap Workflow started at 15:43:04.

Both Argo setup functions publish their UIs and wait for LoadBalancer addresses,
so faster pod networking alone could not remove this delay.

The new dependency graph is defined in [lib/common.sh](../lib/common.sh), with
the network helper in [bin/meshlab](../bin/meshlab):

```text
kind-network -> create-clusters -> cloud-provider-kind -> setup-kubeconfig
             -> pull-through-cache
```

Registry startup stays parallel with cluster creation. Downstream setup retains
failure propagation from cloud-provider-kind. With the new order, the controller
connected to the manager API about 0.2 seconds after starting. CoreDNS setup
also stopped waiting on late LoadBalancer provisioning. Ordering alone did not
demonstrate a total-create improvement with stock Kindnet.

## Full-lab results

All rows below include the one-second Argo CD sync-wave setting.

| Kindnet | Controller ordering | Argo CD setup | Bootstrap Workflow | Full create |
| --- | --- | --- | --- | --- |
| Patched | Original | 23s | 45s | 88s |
| Stock | After clusters | 24s | 45s | 90s |
| Patched | After clusters | 14s | 38s | 71s |
| Patched | After clusters, repeat | 14s | 51s | 84s |
| Stock, restored | After clusters | 24s | 45s | 88s |

The restored run also included the explicit `setup-kubeconfig` dependency on
cloud-provider-kind. Workflow time is the Workflow's start-to-finish duration,
not the enclosing meshlab section, which includes additional overhead.

The repeatable result is the 10-second Argo CD setup reduction. The 13-second
workflow variation between patched runs explains their total-time difference;
the fastest run must not be presented as a guaranteed 19-second saving. In the
slower repeat, the metrics-server task took 28 seconds and Kiali operator took
25 seconds, providing candidates for a separate investigation.

Earlier, independently measured sync-wave tuning gave a baseline create time of
89 seconds and candidate times of 83, 83, and 82 seconds. Workflow time fell from
45 seconds to 39, 40, and 38 seconds. These separate runs are not interchangeable
with the Kindnet controls above.

## Reproducing the experiment

Use a disposable lab: the full-lab procedure deletes its clusters. Requirements
include Docker, kind, kubectl, Go, Helm, jq, and Mike Farah's yq v4.

1. Fetch the pinned kind source and apply the import and cache-sync block above.
   The tested source archive was
   `https://codeload.github.com/kubernetes-sigs/kind/tar.gz/69b56db7`.
2. In `images/kindnetd`, run `go test ./cmd/kindnetd` and
   `CGO_ENABLED=0 go build -o /tmp/kindnetd ./cmd/kindnetd`. Build for the node
   architecture; the original experiment used `linux/arm64`.
3. For an isolated image test, build this image with the binary in its context:

   ```dockerfile
   FROM docker.io/kindest/kindnetd:v20260820-69b56db7
   COPY --chmod=0755 kindnetd /bin/kindnetd
   ```

4. Create separate stock and patched clusters with `networking.disableDefaultCNI:
   true`, PodSubnet `10.71.0.0/16`, and service subnet `10.171.0.0/16`. Extract
   `/kind/manifests/default-cni.yaml` from the pinned node image. Set the DaemonSet
   image, `POD_SUBNET`, and `CONTROL_PLANE_ENDPOINT` for each test, then apply it.
   When a multi-platform image import fails on missing layers, import only the
   host platform using `ctr --namespace=k8s.io images import --platform linux/arm64 -`
   inside the node, fed by `docker save`.
5. Record Kindnet's API-connection and first `Handling node` log timestamps, the
   CNI file's modification timestamp, and the node Ready transition. Delete the
   disposable clusters when finished.

For the full-lab probe, a temporary wrapper around `kind` modified the generated
cluster configuration before creation. Each node received read-only mounts of
the experimental binary directory at `/opt/kindnet-experiment` and a modified CNI
manifest at `/kind/manifests/default-cni.yaml`. That manifest added a hostPath
volume and set the Kindnet container command to
`/opt/kindnet-experiment/kindnetd`. Thus all other contents of the stock image were
retained. This internal manifest override is undocumented and not a supported
meshlab installation path.

Two important details when recreating that wrapper:

- Docker host paths must use the host workspace path (`LOCAL_WORKSPACE_FOLDER`),
  not assume the devcontainer's `/workspaces/meshlab` path exists on the daemon host.
- Preserve the literal string `{{ .PodSubnet }}` in the bootstrap manifest.
  Processing its unquoted template with yq can turn it into a YAML mapping and
  prevent CNI installation; explicitly assign it as a string after processing.

Invoke the wrapper only through a per-command `PATH` override for `meshlab create`.
Restore with normal `meshlab delete` and `meshlab create`, without that override.
Verify the resulting Kindnet DaemonSets have the stock image, no custom command,
and no experimental volume. Temporary source, binaries, and scripts from this
session were kept in `/tmp/meshlab-kindnet-research`; they are not committed and
must not be treated as durable repository artifacts.

## Validation and limitations

Shell syntax, dependency assertions, and a dry run of the generated Make DAG
passed. Full rebuilds succeeded. After restoration, all 28 Argo CD applications
were Healthy, all three nodes and pods were Ready, all workload-cluster
certificates and ClusterIssuers were Ready, and pod restart counts were zero.
The manager cluster does not install cert-manager, so certificate checks apply
only to `pasta-1` and `pasta-2`.

Networking did **not** pass an all-pairs check. Peer logs showed connection resets
on cross-cluster ambient/sidecar paths with both the patched and stock Kindnet.
The final stock matrix had successful observations for 48 of 64 pairs, with the
16 cross-cluster mixed-mode pairs lacking successes. Reproduction on stock means
this is not unique to the experimental binary; it does not establish the root
cause or prove the patch is regression-free.

Workers initially wait 60 seconds before polling their service list, so a matrix
captured immediately after creation can be empty. Use the repository's
connectivity-matrix script after traffic begins. Ready pods and Healthy Argo CD
applications are not substitutes for successful mesh traffic.