# multi-primary-mesh

Multi-primary Istio mesh with a non-k8s workload running on a VM.
```bash
./bin/launch # Deploy the lab
./bin/delete # Destroy the lab
./bin/argocd # Print ArgoCD details
```

ArgoCD is used to deploy:
- https://github.com/h0tbird/istio
- https://github.com/h0tbird/httpbin

## Local pull-through registries

List images in pull-through registries:
```bash
curl -s 192.168.64.1:5001/v2/_catalog | jq # docker.io
curl -s 192.168.64.1:5002/v2/_catalog | jq # quay.io
curl -s 192.168.64.1:5003/v2/_catalog | jq # ghcr.io
```

List tags for a given image:
```
curl -s 192.168.64.1:5002/v2/argoproj/argocd/tags/list | jq
```

Get the manifest for a given image and tag:
```
curl -s http://192.168.64.1:5002/v2/argoproj/argocd/manifests/v2.4.7 | jq
```

## Cloud-init

Tail the cloud-init logs:
```
multipass exec kube-00 -- tail -f /var/log/cloud-init-output.log
multipass exec kube-01 -- tail -f /var/log/cloud-init-output.log
multipass exec kube-02 -- tail -f /var/log/cloud-init-output.log
```

Inspect the rendered `runcmd`:
```
multipass exec kube-00 -- sudo cat /var/lib/cloud/instance/scripts/runcmd
multipass exec kube-01 -- sudo cat /var/lib/cloud/instance/scripts/runcmd
multipass exec kube-02 -- sudo cat /var/lib/cloud/instance/scripts/runcmd
multipass exec virt-01 -- sudo cat /var/lib/cloud/instance/scripts/runcmd
```

## ArgoCD

List all applications:
```
argocd app list
```

Manually sync applications:
```
argocd app sync kube-01-istio-base kube-02-istio-base
argocd app sync kube-01-istio-cni kube-02-istio-cni
argocd app sync kube-01-istio-pilot kube-02-istio-pilot
argocd app sync kube-01-istio-igws kube-02-istio-igws
argocd app sync kube-01-istio-ewgw kube-02-istio-ewgw
argocd app sync kube-01-httpbin kube-02-httpbin
```

## Remote clusters

List the remote clusters:
```
istioctl --context kube-01 remote-clusters
istioctl --context kube-02 remote-clusters
```

## Calico

Query Calico:
```
calicoctl get ipPool -o wide --allow-version-mismatch
calicoctl get node -o wide --allow-version-mismatch
```

## Envoy

Inspect the `config_dump` of a VM:
```
multipass exec virt-01 -- curl -s localhost:15000/config_dump | istioctl pc listeners --file -
multipass exec virt-01 -- curl -s localhost:15000/config_dump | istioctl pc routes --file -
multipass exec virt-01 -- curl -s localhost:15000/config_dump | istioctl pc clusters --file -
multipass exec virt-01 -- curl -s localhost:15000/config_dump | istioctl pc secret --file -
```

Set debug log level on a given proxy:
```
istioctl pc log sleep-xxx.httpbin --level debug
k --context kube-01 -n httpbin logs -f sleep-xxx -c istio-proxy
```

Access the WebUI of a given envoy proxy:
```
istioctl dashboard envoy sleep-xxx.httpbin
```

Access the WebUI of `istiod`:
```
istioctl dashboard controlz deployment/istiod-1-14-2.istio-system
```

Dump the `common_tls_context` for a given envoy cluster:
```
k --context kube-01 -n httpbin exec -i sleep-xxx -- \
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

## TLS v1.3 troubleshooting

A place to dump the crypto material:
```
k --context kube-01 -n httpbin patch deployment sleep --type merge -p '
spec:
  template:
    metadata:
      annotations:
        sidecar.istio.io/userVolume: "[{\"name\":\"sniff\", \"emptyDir\":{\"medium\":\"Memory\"}}]"
        sidecar.istio.io/userVolumeMount: "[{\"name\":\"sniff\", \"mountPath\":\"/sniff\"}]"
        proxy.istio.io/config: |
          proxyMetadata:
            OUTPUT_CERTS: /sniff
'
```

Write the required per-session TLS secrets to a file ([source](https://github.com/istio/istio/blob/5f90e4b9ae19800f4c539628ae038ec118835610/pilot/pkg/networking/core/v1alpha3/envoyfilter/cluster_patch_test.go#L241-L262)):
```
k --context kube-01 apply -f - << EOF
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: httpbin
  namespace: httpbin
spec:
  workloadSelector:
    labels:
      app: sleep
  configPatches:
  - applyTo: CLUSTER
    match:
      context: SIDECAR_OUTBOUND
      cluster:
        service: "httpbin.httpbin.svc.cluster.local"
        portNumber: 80
    patch:
      operation: MERGE
      value:
        transport_socket:
          name: "envoy.transport_sockets.tls"
          typed_config:
            "@type": "type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext"
            common_tls_context:
              key_log:
                path: /sniff/keylog
EOF
```

Restart envoy to kill all TCP connections and force new TLS handshakes:
```
k --context kube-01 -n httpbin exec -it sleep-xxx -c istio-proxy -- curl -X POST localhost:15000/quitquitquit
```

Optionally, use this command to list all available endpoints:
```
istioctl --context kube-01 pc endpoint deploy/httpbin.httpbin | egrep '^END|httpbin'
```

Start `tcpdump`:
```
k --context kube-01 -n httpbin exec -it sleep-xxx -c istio-proxy -- sudo tcpdump -s0 -w /sniff/dump.pcap
```

Send a few requests to the endpoints listed above:
```
k --context kube-01 -n httpbin exec -i sleep-xxx -- curl -s http://httpbin/get | jq -r '.envs."HOSTNAME"'
```

Download everything:
```
k --context kube-01 -n httpbin cp -c istio-proxy sleep-xxx:sniff ~/sniff
```

Open it with Wireshark:
```
open ~/sniff/dump.pcap
```

Filter by `tls.handshake.type == 1` and follow the TLS stream of a `Client Hello` packet. 
Right click a `TLSv1.3` packet then `Protocol Preferences` --> `Transport Layer Security` --> `(Pre)-Master-Secret log filename` and provide the path to the `keylog` file.

## Testing

Send requests to service `httpbin`:
```
k --context kube-01 -n httpbin exec -i sleep-xxx -- curl -s httpbin/get | jq -r '.envs."HOSTNAME"'
k --context kube-02 -n httpbin exec -i sleep-xxx -- curl -s httpbin/get | jq -r '.envs."HOSTNAME"'
```

Same thing but using the VM:
```
for i in {1..6}; do multipass exec virt-01 -- curl -s httpbin/get | jq -r '.envs."HOSTNAME"'; done
```

## Certificates

Connect to the externally exposed `istiod` service and inspect the certificate bundle it presents:
```
step certificate inspect --bundle --servername istiod-1-14-2.istio-system.svc https://192.168.64.3:15012 --roots ./tmp/istio-ca/root-cert.pem
step certificate inspect --bundle --servername istiod-1-14-2.istio-system.svc https://192.168.64.3:15012 --insecure
```

As a client, inspect the certificate provided by a workload:
```
k -n httpbin exec -it sleep-xxx -c istio-proxy -- openssl s_client -showcerts httpbin:80
```

## Workload endpoints

List all the endpoints for a given cluster and workload:
```
istioctl --context kube-01 pc endpoint deploy/httpbin.httpbin | egrep '^END|httpbin'
istioctl --context kube-02 pc endpoint deploy/httpbin.httpbin | egrep '^END|httpbin'
```

## Devel

Provision only one VM:
```
source ./lib/misc.sh && launch_k8s kube-00
source ./lib/misc.sh && launch_vms virt-01
```
