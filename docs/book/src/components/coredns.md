# CoreDNS

[CoreDNS](https://coredns.io) is a flexible, extensible DNS server that can be easily configured to provide custom DNS resolutions in Kubernetes clusters. It allows for dynamic updates, service discovery, and integration with external data sources, making it a popular choice for service discovery and network management in cloud-native environments.

Create a DNS record for `demo.lab`:
```console
k --context pasta-1 -n kube-system create configmap coredns-custom --from-literal=demo.server='demo.lab {
  hosts {
    ttl 60
    192.168.64.3 echo.blau.demo.lab
    192.168.64.3 httpbin.blau.demo.lab
    192.168.64.3 echo.verd.demo.lab
    192.168.64.3 httpbin.verd.demo.lab
    fallthrough
  }
}'
```
