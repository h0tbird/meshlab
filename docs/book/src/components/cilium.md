# Cilium

[Cilium](https://cilium.io/) is an open source, cloud native solution for providing, securing, and observing network connectivity between workloads, fueled by the revolutionary Kernel technology eBPF.

Display status:
```console
cilium --context pasta-1 status
```

Show status of ClusterMesh:
```
cilium --context pasta-1 clustermesh status
```

Display status of daemon:
```console
k --context pasta-1 -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status
```

Display full details:
```console
k --context pasta-1 -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status --verbose
```

List services:
```console
k --context pasta-1 -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg service list
```

Troubleshoot connectivity towards remote clusters:
```console
k --context pasta-1 -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg troubleshoot clustermesh
```
