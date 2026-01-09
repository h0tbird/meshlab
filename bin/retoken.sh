#!/bin/bash

SRC_CLUSTER="pasta-1"
DST_CLUSTER="pasta-2"

retoken () {
  # New KUBECONFIG for $DST_CLUSTER with updated token
  KUBECONFIG_B64=$(k --context kind-$SRC_CLUSTER -n istio-system get secret istio-remote-secret-$DST_CLUSTER -o yaml | yq ".data.$DST_CLUSTER" |
  base64 -d | yq ".users[0].user.token = \"$(k --context kind-$DST_CLUSTER -n istio-system create token istio-reader-service-account)\"" | base64 -w0)

  # Edit secret istio-remote-secret-$DST_CLUSTER in $SRC_CLUSTER
  k --context kind-$SRC_CLUSTER -n istio-system patch secret istio-remote-secret-$DST_CLUSTER \
  -p "{\"data\":{\"$DST_CLUSTER\":\"${KUBECONFIG_B64}\"}}"
}

# Take the initial heap profile
echo "Taking initial heap profile sample 0"
curl -s "http://localhost:9090/debug/pprof/heap" > heap.sample-0.pb.gz

# Run retoken and take heap profile sample every 10 retokenings
sample=1
for i in {1..100}; do
  retoken
  sleep 10
  if (( i % 10 == 0 )); then
    echo "Taking heap profile sample ${sample}"
    curl -s "http://localhost:9090/debug/pprof/heap" > heap.sample-"${sample}".pb.gz
    ((sample++))
  fi
done

# k --context kind-pasta-1 -n istio-system port-forward deployments/istiod-1-28-2 9090:8080
# go tool pprof -http=:9999 -diff_base heap.sample-0.pb.gz heap.sample-10.pb.gz