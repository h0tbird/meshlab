# Testing

Send requests to `service-1` from an unauthenticated out-of-cluster workstation via the north-south Istio ingress gateway:
```console
IP=$(multipass list | awk '/pasta-1/ {print $3}')
curl -sk --resolve service-1.demo.lab:443:${IP} https://service-1.demo.lab/data | jq -r '.podName'
```

Same as above but with certificate validation:
```console
IP=$(multipass list | awk '/pasta-1/ {print $3}')
k --context pasta-1 -n istio-system get secret cacerts -o json | jq -r '.data."ca.crt"' | base64 -d > /tmp/ca.crt
curl -s --cacert /tmp/ca.crt --resolve service-1.demo.lab:443:${IP} https://service-1.demo.lab/data | jq -r '.podName'
```
