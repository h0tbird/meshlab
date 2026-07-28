# CoreDNS

[CoreDNS](https://coredns.io) is the in-cluster DNS server. The lab rewrites its
`Corefile` on every cluster (the `setup-coredns` section) for two reasons.

## 1. The cluster zone is `<cell>.local`

kind clusters are created with kubeadm `networking.dnsDomain: <cell>.local`, so
the `kubernetes` plugin must serve `pasta.local` (or `pizza.local`, or
`mngr.local`) instead of the default `cluster.local`:

```
kubernetes pasta.local in-addr.arpa ip6.arpa {
   pods insecure
   fallthrough in-addr.arpa ip6.arpa
   ttl 30
}
```

Caching of that zone is explicitly disabled (`cache 30 { disable success
pasta.local; disable denial pasta.local }`) so cross-cluster service changes are
picked up promptly.

## 2. `demo.lab` resolves to LoadBalancer IPs

An extra server block forwards the `demo.lab` zone to the
[k8s_gateway](https://github.com/k8s-gateway/k8s_gateway) instance running on
the manager cluster (installed by `install-k8s-gateway` as the `exdns` release
in `kube-system`):

```
demo.lab:53 {
   forward . <exdns-k8s-gateway LoadBalancer IP>
}
```

k8s_gateway synthesises `A` records for `Service`/`Gateway` objects, which is
how names like `prometheus.demo.lab` — used by the OpenTelemetry collectors to
remote-write from every cluster — resolve to the right `LoadBalancer` IP.

## Everyday commands

Show the effective config:
```console
k --context kind-pasta-1 -n kube-system get cm coredns -o jsonpath='{.data.Corefile}'
```

Resolve a name from inside a cluster:
```console
k --context kind-pasta-1 -n swarm-ambient-n1 exec deploy/peer -c manager -- \
  nslookup prometheus.demo.lab
```

Re-apply the config (restarts CoreDNS only if it actually changed):
```console
meshlab run setup-coredns
```
