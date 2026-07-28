# Debug

## Cluster overview

```console
ml            # pods + LoadBalancer services on every cluster
ml short      # only mnger-1 and pasta-1
meshlab watch # `ml short` on a loop
```

## Failed sections

`meshlab create` runs with `make -k`, so it keeps going after a failure and
records the offenders in `.tmp/failed`. Re-run just those:

```console
cat .tmp/failed
meshlab run <section>
```

Section logs that run detached are also under `.tmp/` (for example
`.tmp/tilt-pasta-1.log`).

## Locality labels

Locality is derived from the node's `topology.kubernetes.io/*` labels, which
kind does not set. Add them manually to experiment with
[locality load balancing](./locality-lb.md):

```console
k --context kind-pasta-1 label node pasta-1-control-plane \
  topology.kubernetes.io/region=milky-way \
  topology.kubernetes.io/zone=solar-system \
  topology.istio.io/subzone=pasta-1
```

Or override it per workload with the `istio-locality` pod label
(`<region>/<zone>/<subzone>`, dots instead of slashes in the label value):

```console
k --context kind-pasta-1 -n swarm-sidecar-n1 patch deployment peer --type merge -p \
  '{"spec":{"template":{"metadata":{"labels":{"istio-locality":"milky-way.solar-system.pasta-1"}}}}}'
```

Remove it again:
```console
k --context kind-pasta-1 -n swarm-sidecar-n1 patch deployment peer --type json -p \
  '[{"op":"remove","path":"/spec/template/metadata/labels/istio-locality"}]'
k --context kind-pasta-1 label node pasta-1-control-plane \
  topology.kubernetes.io/region- topology.kubernetes.io/zone- topology.istio.io/subzone-
```

## Custom istiod / proxy images

For a one-off image swap (for a persistent change, edit the istiod
`ApplicationSet` — otherwise Argo CD will revert it):

```console
k --context kind-pasta-1 -n istio-system set image deployment/istiod-1-30-3 \
  discovery=ghcr.io/h0tbird/pilot:1.30.3-dev

k --context kind-pasta-1 -n swarm-sidecar-n1 patch deployment peer --type merge -p \
  '{"spec":{"template":{"metadata":{"annotations":{"sidecar.istio.io/proxyImage":"ghcr.io/h0tbird/proxyv2:1.30.3-dev"}}}}}'
```

For iterating on `pilot-discovery` itself, prefer Tilt — see
[Development](./development.md).

## Attaching a debugger to istiod

`hack/launch.json` holds the matching VS Code launch configuration.

```console
k --context kind-pasta-1 -n istio-system exec -it deployment/istiod-1-30-3 -- \
  dlv dap --listen=:40000 --log=true
k --context kind-pasta-1 -n istio-system port-forward deployment/istiod-1-30-3 40000:40000
```

To attach to a proxy, first relax `ptrace_scope` in the debug-variant proxy
container:
```console
k --context kind-pasta-1 -n swarm-sidecar-n1 exec -it deploy/peer -c istio-proxy -- \
  sudo bash -c 'echo 0 > /proc/sys/kernel/yama/ptrace_scope'
```

## More

`docs/troubleshooting.md` in this repository collects issue-specific
write-ups that are too narrow for the book.
