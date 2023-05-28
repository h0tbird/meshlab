# Envoy

Envoy is an open-source proxy server designed for modern microservices
architectures, providing features such as load balancing, traffic management,
and service discovery. It runs standalone or integrated with a service mesh,
making it a powerful tool for microservices communication.

Inspect the `config_dump` of a VM:
```console
multipass exec virt-01 -- curl -s localhost:15000/config_dump | istioctl pc listeners --file -
multipass exec virt-01 -- curl -s localhost:15000/config_dump | istioctl pc routes --file -
multipass exec virt-01 -- curl -s localhost:15000/config_dump | istioctl pc clusters --file -
multipass exec virt-01 -- curl -s localhost:15000/config_dump | istioctl pc secret --file -
```

Set debug log level on a given proxy:
```console
istioctl pc log sleep-xxx.httpbin --level debug
k --context pasta-1 -n httpbin logs -f sleep-xxx -c istio-proxy
```

Access the WebUI of a given envoy proxy:
```console
istioctl dashboard envoy sleep-xxx.httpbin
```

Dump the envoy config of an eastweast gateway:
```console
k --context pasta-1 -n istio-system exec -it deployment/istio-eastwestgateway -- curl -s localhost:15000/config_dump
```

Dump the `common_tls_context` for a given envoy cluster:
```console
k --context pasta-1 -n httpbin exec -i sleep-xxx -- \
curl -s localhost:15000/config_dump | jq '
  .configs[] |
  select(."@type"=="type.googleapis.com/envoy.admin.v3.ClustersConfigDump") |
  .dynamic_active_clusters[] |
  select(.cluster.name=="outbound|80||httpbin.httpbin.svc.cluster.local") |
  .cluster.transport_socket_matches[] |
  select(.name=="tlsMode-istio") |
  .transport_socket.typed_config.common_tls_context
'
```

List `LISTEN` ports:
```console
k --context pasta-1 -n istio-system exec istio-eastwestgateway-xxx -- netstat -tuanp | grep LISTEN | sort -u
```

Check the status-port:
```console
curl -o /dev/null -Isw "%{http_code}" http://10.0.16.124:31123/healthz/ready
```
