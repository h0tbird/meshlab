# Flannel

[Flannel](https://github.com/flannel-io/flannel) is a lightweight provider of layer 3 network fabric that implements the Kubernetes Container Network Interface (CNI). Flannel allocates a subnet lease to each host out of a larger, preconfigured address space. Packets are forwarded using one of several backend mechanisms including VXLAN and `host-gw`.

CNI conf dir:
```console
multipass exec pasta-1 -- bash -c "sudo ls -la /var/lib/rancher/k3s/agent/etc/cni/net.d"
```

CNI bin dir:
```console
multipass exec pasta-1 -- bash -c "sudo ls -la /var/lib/rancher/k3s/data/current/bin"
```
