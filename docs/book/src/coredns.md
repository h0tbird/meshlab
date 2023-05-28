# CoreDNS

CoreDNS is a flexible, extensible DNS server that can be easily configured to
provide custom DNS resolutions in Kubernetes clusters. It allows for dynamic
updates, service discovery, and integration with external data sources, making
it a popular choice for service discovery and network management in
cloud-native environments.

Create a DNS record for `httpbin.demo.com`:
```console
k --context pasta-1 -n kube-system create configmap coredns-custom --from-literal=demo.server='demo.com {
  hosts {
    ttl 60
    192.168.64.3 httpbin.demo.com
    fallthrough
  }
}'
```

Create a DNS record for `httpbin.demo.com`:
```console
k --context pasta-2 -n kube-system create configmap coredns-custom --from-literal=demo.server='demo.com {
  hosts {
    ttl 60
    192.168.64.4 httpbin.demo.com
    fallthrough
  }
}'
```
