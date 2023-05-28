
## Locality load balancing

Istio's Locality Load Balancing (LLB) is a feature that helps distribute
traffic across different geographic locations in a way that minimizes latency
and maximizes availability. It routes traffic to the closest available instance
of the service, reducing network hops and improving performance, while also
providing fault tolerance and resilience. LLB is important for managing
microservices architectures.

<details><summary>Click me</summary><p>

`applab-blau` priority and weight from the point of view of the `istio-ingressgateway`:
```console
watch "istioctl --context pasta-1 -n istio-system pc endpoint deploy/istio-ingressgateway | grep -E '^END|applab-blau'; echo; k --context pasta-1 -n istio-system exec -it deployment/istio-ingressgateway -- curl -X POST localhost:15000/clusters | grep '^outbound.*applab-blau' | grep -E 'zone|region|::priority|::weight' | sort | sed -e '/:zone:/s/$/\n/'"
watch "istioctl --context pasta-2 -n istio-system pc endpoint deploy/istio-ingressgateway | grep -E '^END|applab-blau'; echo; k --context pasta-2 -n istio-system exec -it deployment/istio-ingressgateway -- curl -X POST localhost:15000/clusters | grep '^outbound.*applab-blau' | grep -E 'zone|region|::priority|::weight' | sort | sed -e '/:zone:/s/$/\n/'"
```

`applab-blau` workloads, priority and weight from the point of view of the `sleep` pod:
```console
watch "k --context pasta-1 -n applab-blau get po -o wide; echo; istioctl --context pasta-1 -n applab-blau pc endpoint deploy/sleep | grep -E '^END|applab-blau'; echo; k --context pasta-1 -n applab-blau exec -it deployment/sleep -c istio-proxy -- curl -X POST localhost:15000/clusters | grep '^outbound.*applab-blau' | grep -E 'zone|region|::priority|::weight' | sort | sed -e '/:zone:/s/$/\n/'"
watch "k --context pasta-2 -n applab-blau get po -o wide; echo; istioctl --context pasta-2 -n applab-blau pc endpoint deploy/sleep | grep -E '^END|applab-blau'; echo; k --context pasta-2 -n applab-blau exec -it deployment/sleep -c istio-proxy -- curl -X POST localhost:15000/clusters | grep '^outbound.*applab-blau' | grep -E 'zone|region|::priority|::weight' | sort | sed -e '/:zone:/s/$/\n/'"
```

`VM`: patch the `workloadentries` object with locality metadata (bug?):
```console
k --context pasta-1 -n httpbin patch workloadentries httpbin-192.168.64.5-vm-network --type merge -p '{"spec":{"locality":"milky-way/solar-system/virt-01"}}'
```

`VM`: retrieve topology metadata, assigned priority and weight:
```console
multipass exec virt-01 -- curl -s localhost:15000/clusters | grep '^outbound|80||httpbin' | grep -E 'zone|region|::priority|::weight' | sort | sed -e '/:zone:/s/$/\n/'
```

</p></details>

## Testing

The tests in this section should validate all functionalities.

<details><summary>Click me</summary><p>

Send requests to the `blau` services from an authenticated in-cluster pod:
```console
k --context pasta-1 -n applab-blau exec -i deployment/sleep -- curl -s httpbin/hostname | jq -r '.hostname'
k --context pasta-1 -n applab-blau exec -i deployment/sleep -- bash -c "echo hello | nc -N echo 70"
```

Send requests to the `blau` services from an unauthenticated out-of-cluster workstation:
```console
curl -skm2 --resolve httpbin.blau.demo.lab:443:192.168.64.3 https://httpbin.blau.demo.lab/hostname | jq -r '.hostname'
echo hello | gnutls-cli 192.168.64.3 -p 70 --sni-hostname echo.blau.demo.lab --insecure --logfile=/tmp/echo.log
```

Same as above but with certificate validation:
```console
k --context pasta-1 -n istio-system get secret cacerts -o json | jq -r '.data."ca.crt"' | base64 -d > /tmp/ca.crt
curl -sm 2 --cacert /tmp/ca.crt --resolve httpbin.blau.demo.lab:443:192.168.64.3 https://httpbin.blau.demo.lab/get | jq -r '.envs.HOSTNAME'
echo hello | openssl s_client -servername echo.blau.demo.lab -connect 192.168.64.3:70 -quiet -CAfile /tmp/ca.crt
```

Send requests to the `blau` service from an authenticated out-of-cluster VM:
```console
for i in {1..20}; do multipass exec virt-01 -- curl -s httpbin/hostname | jq -r '.hostname'; done | sort | uniq -c | sort -rn
```

</p></details>

## TLS 1.3

TLS 1.3 is the latest version of the TLS protocol. TLS, which is used by HTTPS
and other network protocols for encryption, is the modern version of SSL. TLS
1.3 dropped support for older, less secure cryptographic features, and it
speeds up TLS handshakes, among other improvements.

<details><summary>Click me</summary><p>

Setup a place to dump the crypto material:
```console
k --context pasta-1 -n httpbin patch deployment sleep --type merge -p '
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
```console
k --context pasta-1 apply -f - << EOF
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
```console
k --context pasta-1 -n httpbin exec -it deployment/sleep -c istio-proxy -- curl -X POST localhost:15000/quitquitquit
```

Optionally, use this command to list all available endpoints:
```console
istioctl --context pasta-1 pc endpoint deploy/httpbin.httpbin | egrep '^END|httpbin'
```

Start `tcpdump`:
```console
k --context pasta-1 -n httpbin exec -it deployment/sleep -c istio-proxy -- sudo tcpdump -s0 -w /sniff/dump.pcap
```

Send a few requests to the endpoints listed above:
```console
k --context pasta-1 -n httpbin exec -i deployment/sleep -- curl -s httpbin/hostname | jq -r 'hostname'
```

Stop `tcpdump` and download everything:
```console
k --context pasta-1 -n httpbin cp -c istio-proxy sleep-xxx:sniff ~/sniff
```

Open it with Wireshark:
```console
open ~/sniff/dump.pcap
```

Filter by `tls.handshake.type == 1` and follow the TLS stream of a `Client Hello` packet. 
Right click a `TLSv1.3` packet then `Protocol Preferences` --> `Transport Layer Security` --> `(Pre)-Master-Secret log filename` and provide the path to the `keylog` file.

</p></details>

## Certificates

Find below a collection of commands to troubleshoot certificate issues.

<details><summary>Click me</summary><p>

Connect to the externally exposed `istiod` service and inspect the certificate bundle it presents:
```console
step certificate inspect --bundle --servername istiod-1-17-2.istio-system.svc https://192.168.64.3:15012 --roots /path/to/root-ca.pem
step certificate inspect --bundle --servername istiod-1-17-2.istio-system.svc https://192.168.64.3:15012 --insecure
```

Inspect the certificate chain provided by a given workload:
```console
istioctl --context pasta-2 pc secret httpbin-xxxxxxxxxx-yyyyy.httpbin -o json | jq -r '.dynamicActiveSecrets[] | select(.name=="default") | .secret.tlsCertificate.certificateChain.inlineBytes' | base64 -d | step certificate inspect --bundle
```

Inspect the certificate root CA present in a given workload:
```console
istioctl --context pasta-2 pc secret sleep-xxxxxxxxxx-yyyyy.httpbin -o json | jq -r '.dynamicActiveSecrets[] | select(.name=="ROOTCA") | .secret.validationContext.trustedCa.inlineBytes' | base64 -d | step certificate inspect --bundle
```

Similar as above but this time as a client:
```console
k --context pasta-1 -n httpbin exec -it deployment/sleep -c istio-proxy -- openssl s_client -showcerts httpbin:80
```

</p></details>

## Devel

Provision only one VM:
```console
source ./lib/misc.sh && launch_k8s kube-00
source ./lib/misc.sh && launch_vms virt-01
```

## Debug

Add locality info:
```console
k --context pasta-1 -n httpbin patch workloadentries httpbin-192.168.64.5-vm-network --type merge -p '{"spec":{"locality":"milky-way/solar-system/virt-01"}}'
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
k --context pasta-1 -n httpbin patch workloadentries httpbin-192.168.64.5-vm-network --type json -p '[{"op": "remove", "path": "/spec/locality"}]'
k --context pasta-1 -n httpbin patch deployment sleep --type json -p '[{"op": "remove", "path": "/spec/template/metadata/labels/istio-locality"}]'
k --context pasta-1 -n httpbin label pod sleep-xxxx topology.istio.io/subzone- topology.kubernetes.io/region- topology.kubernetes.io/zone-
```

Set debug images:
```console
k --context pasta-1 -n istio-system set image deployment/istiod-1-17-2 discovery=docker.io/h0tbird/pilot:1.17.2
k --context pasta-1 -n httpbin patch deployment sleep --type merge -p '{"spec":{"template":{"metadata":{"annotations":{"sidecar.istio.io/proxyImage":"docker.io/h0tbird/proxyv2:1.17.2"}}}}}'
```

Unset debug images:
```console
k --context pasta-1 -n istio-system set image deployment/istiod-1-17-2 discovery=docker.io/istio/pilot:1.17.2
k --context pasta-1 -n httpbin patch deployment sleep --type merge -p '{"spec":{"template":{"metadata":{"annotations":{"sidecar.istio.io/proxyImage":"docker.io/istio/proxyv2:1.17.2"}}}}}'
```

Debug:
```console
k --context pasta-1 -n httpbin exec -it deployments/sleep -c istio-proxy -- sudo bash -c 'echo 0 > /proc/sys/kernel/yama/ptrace_scope'
k --context pasta-1 -n istio-system exec -it deployments/istiod-1-17-2 -- dlv dap --listen=:40000 --log=true
k --context pasta-1 -n istio-system port-forward deployments/istiod-1-17-2 40000:40000
```
