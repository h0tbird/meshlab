# Pull-through registries

A pull-through registry is a proxy that sits between your local Docker
installation and a remote Docker registry. It caches the images you pull from
the remote registry, and if another user on the same network tries to pull the
same image, the pull-through registry will serve it to them directly, rather
than pulling it again from the remote registry. The Container Runtime Interface
(CRI) in this lab is set up to use local pull-through registries for the
remote registries `docker.io`, `quay.io` and `ghcr.io` on each cluster.

List all images in a registry:
```console
curl -s 127.0.0.1:5011/v2/_catalog | jq # docker.io
curl -s 127.0.0.1:5012/v2/_catalog | jq # quay.io
curl -s 127.0.0.1:5013/v2/_catalog | jq # ghcr.io
```

List tags for a given image:
```console
curl -s 127.0.0.1:5012/v2/argoproj/argocd/tags/list | jq
```

Get the manifest for a given image and tag:
```console
curl -s http://127.0.0.1:5012/v2/argoproj/argocd/manifests/v2.4.7 | jq
```
