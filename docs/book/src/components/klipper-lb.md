# klipper-lb

`klipper-lb` uses a host port for each `Service` of type `LoadBalancer` and
sets up iptables to forward the request to the cluster IP. The regular k8s
scheduler will find a free host port. If there are no free host ports, the
`Service` will stay in pending. There is one `DaemonSet` per `Service` of type
`LoadBalancer` and each `Pod` has one container per exposed `Service` port.

List the containers fronting the exposed `argocd-server` ports:
```console
k --context mnger-1 -n kube-system get ds -l svccontroller.k3s.cattle.io/svcname=argocd-server -o yaml | yq '.items[].spec.template.spec.containers[].name'
```

List the containers fronting the exposed `istio-eastwestgateway` ports:
```console
k --context pasta-1 -n kube-system get ds -l svccontroller.k3s.cattle.io/svcname=istio-eastwestgateway -o yaml | yq '.items[].spec.template.spec.containers[].name'
```

List the containers fronting the exposed `istio-ingressgateway` ports:
```console
k --context pasta-1 -n kube-system get ds -l svccontroller.k3s.cattle.io/svcname=istio-ingressgateway -o yaml | yq '.items[].spec.template.spec.containers[].name'
```
