# Pull-through cache (zot)

A pull-through cache is a proxy that sits between the clusters and the remote
container registries. The first time an image is pulled it is fetched from the
upstream registry and cached; subsequent pulls of the same image are served from
the cache instead of hitting the upstream again.

This lab runs a single [zot](https://zotregistry.dev/) instance as the
pull-through cache for every upstream registry, replacing the previous trio of
`registry:2` containers. zot runs as a Docker container on the devcontainer host
(attached to the `kind` network) so it is available before any cluster or CNI
exists. It uses zot's `sync` extension in **on-demand** mode: an image is mirrored
from the upstream only when it is first requested, then cached in zot's local
blob store.

Each upstream is mirrored under its own destination prefix:

| Upstream | zot destination | Endpoint |
|----------|-----------------|----------|
| `docker.io` | `/docker.io` | `https://registry-1.docker.io` |
| `quay.io` | `/quay.io` | `https://quay.io` |
| `ghcr.io` | `/ghcr.io` | `https://ghcr.io` |
| `registry.k8s.io` | `/registry.k8s.io` | `https://registry.k8s.io` |
| `registry.istio.io` | `/registry.istio.io` | `https://registry.istio.io` |
| `ecr-public.aws.com` | `/ecr-public.aws.com` | `https://public.ecr.aws` |

The upstreams are defined in a single associative array (`REGISTRIES`) in
`lib/common.sh`; add more by adding a row there.

## How the clusters use it

Each cluster's containerd is configured (via
`/etc/containerd/certs.d/<upstream>/hosts.toml`) to mirror every upstream through
its zot destination prefix, using `override_path = true` so the prefix becomes
the registry API root:

```toml
server = "https://registry-1.docker.io"
[host."http://zot:8080/v2/docker.io"]
  capabilities = ["pull", "resolve"]
  override_path = true
```

A pull of `docker.io/library/nginx` is therefore served from
`http://zot:8080/v2/docker.io/library/nginx`. The `server` line keeps the real
upstream as a fallback if zot is unreachable.

By-digest pulls (`image@sha256:...`) keep working because zot is configured with
`compat: ["docker2s2"]` and the sync `preserveDigest` option, so Docker media
types and digests are preserved instead of being rewritten to OCI.

## Web UI

zot's web interface and `/v2` API are published on the host:

- URL: <http://127.0.0.1:8086>

The UI is part of the same zot binary (the bundled `ui` + `search` extensions) —
no extra component is required.

## API examples

List all cached repositories:
```console
curl -s http://127.0.0.1:8086/v2/_catalog | jq
```

List tags for a cached image (note the destination prefix):
```console
curl -s http://127.0.0.1:8086/v2/quay.io/argoproj/argocd/tags/list | jq
```

Get the manifest for a given image and tag:
```console
curl -s http://127.0.0.1:8086/v2/quay.io/argoproj/argocd/manifests/v2.4.7 | jq
```

## Lifecycle

- zot is installed and started by the `pull-through-cache` section of
  `bin/meshlab`, and the clusters are wired to it by the
  `add-registries-to-containerd` section.
- The rendered config lives in `./.zot/config.json` (gitignored). In this
  devcontainer the Docker CLI talks to the host daemon (Docker-out-of-Docker), so
  the config is bind-mounted read-only from its host path (the workspace is
  bind-mounted into the devcontainer), and the cached blobs are kept in the
  `zot-data` Docker **named volume**.
- The `zot` container is removed on `meshlab delete`, but the `zot-data` volume
  persists, so a subsequent `meshlab create` does not re-download every image.
- To remove zot and its cache entirely:

  ```console
  docker rm -f zot
  docker volume rm zot-data
  ```
