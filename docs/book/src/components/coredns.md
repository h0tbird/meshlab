# CoreDNS

[CoreDNS](https://coredns.io) is a flexible, extensible DNS server that can be easily configured to provide custom DNS resolutions in Kubernetes clusters. It allows for dynamic updates, service discovery, and integration with external data sources, making it a popular choice for service discovery and network management in cloud-native environments.

Create DNS records for `mesh.lab`:
```console
k --context pasta-1 -n kube-system create configmap coredns-custom --from-literal=demo.server='mesh.lab {
  hosts {
    ttl 60
    192.168.65.3 worker.service-1.mesh.lab
    192.168.65.3 worker.service-2.mesh.lab
    fallthrough
  }
}'
```
