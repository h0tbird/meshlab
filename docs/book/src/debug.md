# Debug

Add locality info:
```console
k --context pasta-1 -n httpbin patch workloadentries httpbin-192.168.65.5-vm-network --type merge -p '{"spec":{"locality":"milky-way/solar-system/virt-01"}}'
k --context pasta-1 -n httpbin patch deployment sleep --type merge -p '{"spec":{"template":{"metadata":{"labels":{"istio-locality":"milky-way.solar-system.pasta-1"}}}}}'
k --context pasta-1 -n httpbin label pod sleep-xxxx topology.istio.io/subzone=pasta-1 topology.kubernetes.io/region=milky-way topology.kubernetes.io/zone=solar-system
```

```console
k --context pasta-1 -n httpbin patch deployment sleep --type merge -p '{"spec":{"template":{"metadata":{"labels":{
  "topology.kubernetes.io/region":"milky-way",
  "topology.kubernetes.io/zone":"solar-system",
  "topology.istio.io/subzone":"pasta-1"
}}}}}'
```

Delete locality info:
```console
k --context pasta-1 -n httpbin patch workloadentries httpbin-192.168.65.5-vm-network --type json -p '[{"op": "remove", "path": "/spec/locality"}]'
k --context pasta-1 -n httpbin patch deployment sleep --type json -p '[{"op": "remove", "path": "/spec/template/metadata/labels/istio-locality"}]'
k --context pasta-1 -n httpbin label pod sleep-xxxx topology.istio.io/subzone- topology.kubernetes.io/region- topology.kubernetes.io/zone-
```

Set debug images:
```console
k --context pasta-1 -n istio-system set image deployment/istiod-1-19-6 discovery=docker.io/h0tbird/pilot:1.19.6
k --context pasta-1 -n httpbin patch deployment sleep --type merge -p '{"spec":{"template":{"metadata":{"annotations":{"sidecar.istio.io/proxyImage":"docker.io/h0tbird/proxyv2:1.19.6"}}}}}'
```

Unset debug images:
```console
k --context pasta-1 -n istio-system set image deployment/istiod-1-19-6 discovery=docker.io/istio/pilot:1.19.6
k --context pasta-1 -n httpbin patch deployment sleep --type merge -p '{"spec":{"template":{"metadata":{"annotations":{"sidecar.istio.io/proxyImage":"docker.io/istio/proxyv2:1.19.6"}}}}}'
```

Debug:
```console
k --context pasta-1 -n httpbin exec -it deployments/sleep -c istio-proxy -- sudo bash -c 'echo 0 > /proc/sys/kernel/yama/ptrace_scope'
k --context pasta-1 -n istio-system exec -it deployments/istiod-1-19-6 -- dlv dap --listen=:40000 --log=true
k --context pasta-1 -n istio-system port-forward deployments/istiod-1-19-6 40000:40000
```
