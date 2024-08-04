# Locality load balancing

Istio's Locality Load Balancing (LLB) is a feature that helps distribute
traffic across different geographic locations in a way that minimizes latency
and maximizes availability. It routes traffic to the closest available instance
of the service, reducing network hops and improving performance, while also
providing fault tolerance and resilience. LLB is important for managing
microservices architectures.

`service-1` priority and weight from the point of view of the `istio-ingressgateway`:
```console
watch "istioctl --context pasta-1 -n istio-system pc endpoint deploy/istio-nsgw | grep -E '^END|service-1'; echo; k --context pasta-1 -n istio-system exec -it deployment/istio-nsgw -- curl -X POST localhost:15000/clusters | grep '^outbound.*service-1' | grep -E 'zone|region|::priority|::weight' | sort | sed -e '/:zone:/s/$/\n/'"
```

`VM`: patch the `workloadentries` object with locality metadata (bug?):
```console
k --context pasta-1 -n httpbin patch workloadentries httpbin-192.168.65.5-vm-network --type merge -p '{"spec":{"locality":"milky-way/solar-system/virt-01"}}'
```

`VM`: retrieve topology metadata, assigned priority and weight:
```console
multipass exec virt-01 -- curl -s localhost:15000/clusters | grep '^outbound|80||httpbin' | grep -E 'zone|region|::priority|::weight' | sort | sed -e '/:zone:/s/$/\n/'
```
