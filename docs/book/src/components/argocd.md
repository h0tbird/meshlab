# Argo CD

[Argo CD](https://argo-cd.readthedocs.io/en/stable/) is the GitOps engine of the
lab. It is installed by the `setup-argocd` section into the `argocd` namespace
of the **manager** cluster only, and it manages every other cluster remotely.

- UI: <http://127.0.0.1:8080> (`admin` / `meshlab123`)

## How applications are generated

`register-argocd-clusters` registers each kind cluster as an Argo CD cluster
secret carrying two labels:

- `name=<cluster>` (e.g. `pasta-1`)
- `cell=<cell>` (e.g. `pasta`)

Every chart under `charts/` then ships an `ApplicationSet` with a `clusters`
generator that fans out over those secrets, using `{{name}}` and
`{{metadata.labels.cell}}` to derive per-cluster values such as the Istio
`clusterName`, `network` and `trustDomain`. `install-applicationsets` renders
them with `helm template ./charts/<x> --set chartVersion=<version>` and
server-side applies the result.

The applications are **not** auto-synced: the ordering is driven by the
[Argo Workflows](./argo-workflows.md) bootstrap DAG, which syncs them by label.

## Everyday commands

List all the applications:
```console
argocd app list
```

Manually sync a set of applications (the label matches the `name` label on the
`ApplicationSet` template, so this hits every cluster at once):
```console
argocd app sync -l name=istio-issuers --async
argocd app sync -l name=istio-base --async
argocd app sync -l name=istio-cni --async
argocd app sync -l name=istio-istiod --async
argocd app sync -l name=istio-ztunnel --async
argocd app sync -l name=istio-nsgw --async
argocd app sync -l name=istio-ewgw --async   # multi-network mode only
```

Re-render and re-apply the `ApplicationSet`s after editing a chart:
```console
meshlab run install-applicationsets
```

Inspect the registered clusters and their labels:
```console
argocd cluster list
k --context kind-mnger-1 -n argocd get secrets -l argocd.argoproj.io/secret-type=cluster --show-labels
```
