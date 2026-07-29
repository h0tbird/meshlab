# Development

The lab is designed to iterate on Istio itself. The workspace
(`meshlab.code-workspace`) mounts four repositories side by side:
`/workspaces/meshlab`, `/workspaces/istio`, `/workspaces/k-swarm` and
`/workspaces/kiali-charts` (the Kiali Helm charts).

## Partial labs

`meshlab create` is a graph of idempotent sections, so you rarely need a full
rebuild:

```console
meshlab list                      # all sections
meshlab run <section>             # run one, honouring --cell-count
meshlab create --cell-count 1     # manager + pasta only (the default)
```

## Live-reloading istiod with Tilt

The `tilt-up` section starts one [Tilt](https://tilt.dev) instance per workload
cluster (ports 9091…9094). Tilt watches the `pilot-discovery` binary built from
`/workspaces/istio` and, on every rebuild, syncs it into the running istiod pod
and restarts the process — no image push, no Argo CD sync.

Rebuild the binary and watch Tilt pick it up:

```console
make istio-binaries          # runs `make build-linux` in /workspaces/istio
```

The Tilt UI for `pasta-1` is at <http://127.0.0.1:9091>. The YAML Tilt applies
mirrors what Argo CD applies for the istiod deployment, so the injected live
sync shows up as a diff in the Argo CD UI.

## Building images and charts

```console
make help                                                     # list the targets
make toolbox    REGISTRY=ghcr.io/<you>                        # image used by the Vault WorkflowTemplate
make istio-images ISTIO_HUB=ghcr.io/<you> ISTIO_TAG=<tag>     # push patched Istio images
make istio-charts HUB=ghcr.io/<you> VERSION=<version>
make istio-labels
```

To actually run a custom build, point the istiod `ApplicationSet` at it: the
`hub`/`tag` and `pilot.image` overrides are already present (commented out) in
`charts/istio/templates/applicationsets/istio-istiod.yaml`.

## Building this book

```console
mdbook serve docs/book        # live preview
mdbook build docs/book
```

## Upgrading components

Component versions are the `readonly *_VERSION` / `*_CHART_VERSION` constants at
the top of `bin/meshlab`, and CLI tool versions live in
`.devcontainer/Dockerfile`. The `upgrade-components` skill
(`.github/skills/upgrade-components/`) checks ArtifactHub and GitHub releases
and bumps them.
