Does the TCP connection (`port: 443` --> `nodePort: 30065` --> `targetPort: 8443`) to the `istio-ingressgateway` work?
```
curl -vkm 2 --resolve blau.demo.lab:443:192.168.64.3 https://blau.demo.lab/get
```

Does the `istio-ingressgateway` present the right TLS certificate?
```
step certificate inspect --bundle --servername blau.demo.lab https://192.168.64.3 --insecure
istioctl --context pasta-1 -n istio-system pc secret deploy/istio-ingressgateway
```

Does the `istio-ingressgateway` see the request?
```
istioctl --context pasta-1 -n istio-system pc log deploy/istio-ingressgateway --level debug
k --context pasta-1 -n istio-system logs -f deployments/istio-ingressgateway | grep blau
```

Does the `istio-ingressgateway` know what to do with this request?
```
istioctl --context pasta-1 -n istio-system pc listeners deploy/istio-ingressgateway
istioctl --context pasta-1 -n istio-system pc routes deploy/istio-ingressgateway
istioctl --context pasta-1 -n istio-system pc clusters deploy/istio-ingressgateway
```