# Locality load balancing

Istio's Locality Load Balancing (LLB) is a feature that helps distribute
traffic across different geographic locations in a way that minimizes latency
and maximizes availability. It routes traffic to the closest available instance
of the service, reducing network hops and improving performance, while also
providing fault tolerance and resilience. LLB is important for managing
microservices architectures.

From the perspective of `istio-nsgw`: get the endpoints, priority, and weight of `service-1`:
```console
# Get a running pod name
POD=$(k --context pasta-1 -n istio-system get po -l istio=nsgw --no-headers | awk 'NR==1{print $1}')

# Add an ephemeral container to the running pod
k --context pasta-1 -n istio-system debug -it \
--attach=false --image=istio/base --target=istio-proxy --container=debugger \
${POD} -- bash

# Watch for the endpoints
watch "istioctl --context pasta-1 -n istio-system pc endpoint deploy/istio-nsgw | grep -E '^END|service-1'; echo; k --context pasta-1 -n istio-system exec -it ${POD} -c debugger -- curl -X POST localhost:15000/clusters | grep '^outbound.*service-1' | grep -E 'zone|region|::priority|::weight' | sort | sed -e '/:zone:/s/$/\n/'"
```