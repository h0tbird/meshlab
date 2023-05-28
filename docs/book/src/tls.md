# TLS

TLS 1.3 is the latest version of the TLS protocol. TLS, which is used by HTTPS
and other network protocols for encryption, is the modern version of SSL. TLS
1.3 dropped support for older, less secure cryptographic features, and it
speeds up TLS handshakes, among other improvements.

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
