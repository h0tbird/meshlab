# Quick start

Everything runs inside the repository's dev container, which already ships
`kind`, `kubectl` (aliased to `k`), `helm`, `istioctl`, `argocd`, `argo`,
`swarmctl`, `tilt` and friends. With the **Dev Containers** extension
installed, the preferred way in is:

```console
make -C ~/path/to/meshlab code
```

Run it from the host (not from inside the container). It builds the
`vscode-remote://dev-container+<hex>/...` URI and opens the multi-root
`meshlab.code-workspace` attached to the dev container in one step, so you
don't have to reopen in container and then open the workspace file separately.

Since `-C` makes it work from any directory, it is handy as a shell alias:

```console
alias meshlab='make -C ~/git/h0tbird/meshlab code'
```

Otherwise, open the repo in VS Code, run `Dev Containers: Reopen in Container`,
then `File: Open Workspace from File...` and pick `meshlab.code-workspace`
(see the README for the other options). Finally, open a terminal inside the
container.

## Create the lab

```console
meshlab create
```

This creates the manager cluster plus the `pasta` cell and runs every section
of the bootstrap graph. Useful flags:

```console
meshlab create --cell-count 2          # also create the pizza cell
meshlab create --network-mode single   # one Istio network per cell (no east-west gateways)
```

Watch the clusters converge from a second terminal:

```console
meshlab watch     # loops `ml short`
ml                # one-shot, all clusters
```

## Services

As the lab starts up, these become available on the host:

| Service        | URL                     | Credentials         |
| -------------- | ----------------------- | ------------------- |
| Argo CD        | <http://127.0.0.1:8080> | `admin`/`meshlab123`|
| Argo Workflows | <http://127.0.0.1:8081> | `admin`/`meshlab123`|
| Vault          | <http://127.0.0.1:8082> | token `meshlab123`  |
| Prometheus     | <http://127.0.0.1:8083> | none                |
| Grafana        | <http://127.0.0.1:8084> | anonymous viewer, or `admin`/`meshlab123` |
| Kiali          | <http://127.0.0.1:8085> | none (anonymous)    |
| zot            | <http://127.0.0.1:8086> | none                |
| Tilt `pasta-1` | <http://127.0.0.1:9091> | none                |
| Tilt `pasta-2` | <http://127.0.0.1:9092> | none                |

With `--cell-count 2`, Tilt for `pizza-1` and `pizza-2` is published on 9093
and 9094.

## Talk to the clusters

kubeconfig contexts are named after the kind clusters, so they carry a `kind-`
prefix:

```console
k --context kind-mnger-1 get nodes
k --context kind-pasta-1 -n istio-system get pods
istioctl --context kind-pasta-1 remote-clusters
```

## Re-run a single section

`meshlab create` is a dependency graph of idempotent sections executed with
`make -j`. Any of them can be re-run on its own:

```console
meshlab list                       # list the sections
meshlab run setup-flat-network     # re-run just one
```

## Tear it down

```console
meshlab delete
```

This removes the kind clusters, the `kindccm` load-balancer containers, the zot
container, the Tilt and `socat` processes, and `./.tmp`. The `zot-data` Docker
volume is kept so the next `meshlab create` does not re-download every image.
