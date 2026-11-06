# Development

The lab is designed to iterate on Istio itself. The workspace
(`meshlab.code-workspace`) mounts five repositories side by side:
`/workspaces/meshlab`, `/workspaces/istio`, `/workspaces/k-swarm`,
`/workspaces/kiali-charts` (the Kiali Helm charts) and `/workspaces/kind`.

## GitHub credentials

The Linux devcontainer cannot use the host's macOS Keychain. The Copilot harness
may also strip `GITHUB_TOKEN` from tool shells, even when the runtime inherits it.
Mounting the host's GitHub CLI configuration would not provide the token stored
in macOS Keychain, so the devcontainer provisions its own login during creation.
Export a token on the host before launching meshlab.

Ensure the VS Code process inherits this environment. The creation command feeds
the token to `gh auth login --with-token --insecure-storage`, with token environment
variables unset for that command.
It stores the token in the container's `~/.config/gh/hosts.yml` using a restrictive
`umask 077`. The command assumes `GITHUB_TOKEN` is set; a failed login fails the
creation step. Use a token accepted by `gh auth login` (a classic PAT requires
`repo`, `read:org` and `gist` scopes).

The token is not baked into the image, committed to this repository, or exposed
in Docker container metadata through `containerEnv`. It is stored in plaintext
inside the container. Container processes can read the stored login.
It survives container restarts, but token rotation requires rebuilding the
container or rerunning the `configure-gh` command from
`.devcontainer/devcontainer.json` in a terminal with the updated `GITHUB_TOKEN`.

Verify file-based authentication without relying on inherited token variables:

```sh
env -u GITHUB_TOKEN -u GH_TOKEN gh api user --silent
```

This does not automatically export `GITHUB_TOKEN` in Copilot's tool shells.
Lab scripts that require the variable can explicitly read the stored login:

```sh
GITHUB_TOKEN="$(gh auth token --hostname github.com)" || exit
export GITHUB_TOKEN
meshlab run grafana-git-sync
```

Do not print the token or enable shell tracing when retrieving it.

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
(`.github/skills/upgrade-components/`) checks upstream chart repositories and
stable releases and bumps them.

Keep the Argo CD CLI version in
`charts/wftemplates/templates/argocd-sync-and-wait.yaml` in sync with the
devcontainer, and update the Vault CLI in `hack/Dockerfile.toolbox` alongside
the devcontainer's Vault CLI. Rebuild and push the toolbox image with
`make toolbox REGISTRY=ghcr.io/<you>` for the workflow to use the new version.

Istio upgrades also require updating both version variables in `Tiltfile`,
checking out the matching upstream tag in `/workspaces/istio`, and rebuilding
the images and binaries with the targets above. After deployment, check the
Argo CD diff for any upstream istiod Deployment changes that need to be
mirrored in `Tiltfile`.
