# Locality load balancing

Istio's Locality Load Balancing (LLB) is a feature that helps distribute
traffic across different geographic locations in a way that minimizes latency
and maximizes availability. It routes traffic to the closest available instance
of the service, reducing network hops and improving performance, while also
providing fault tolerance and resilience. LLB is important for managing
microservices architectures.

> **In this lab, locality is not configured out of the box.** kind nodes carry
> no `topology.kubernetes.io/*` labels, so every endpoint ends up in the same
> (empty) locality. See [Debug](./debug.md) for how to label the nodes or the
> workloads before experimenting.
>
> LLB is also a **sidecar/waypoint** feature. ztunnel ignores
> `DestinationRule.trafficPolicy.loadBalancer` entirely and picks an endpoint at
> random, per TCP connection; the way to express same-cluster preference for
> ambient is `trafficDistribution: PreferClose` on the `Service`. The details
> are written up in `docs/single-network-mode.md`.

From the perspective of `istio-nsgw`: get the endpoints, priority, and weight of
the `peer` service:
```console
# Get a running gateway pod name
POD=$(k --context kind-pasta-1 -n istio-system get po -l istio=nsgw --no-headers | awk 'NR==1{print $1}')

# Add an ephemeral container to the running pod
k --context kind-pasta-1 -n istio-system debug -it \
--attach=false --image=istio/base --target=istio-proxy --container=debugger \
${POD} -- bash

# Watch the endpoints
watch "istioctl --context kind-pasta-1 -n istio-system pc endpoint deploy/istio-nsgw | grep -E '^END|peer'; echo; k --context kind-pasta-1 -n istio-system exec -it ${POD} -c debugger -- curl -X POST localhost:15000/clusters | grep '^outbound.*peer' | grep -E 'zone|region|::priority|::weight' | sort | sed -e '/:zone:/s/$/\n/'"
```
