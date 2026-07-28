# TLS

TLS 1.3 is the latest version of the TLS protocol. TLS, which is used by HTTPS
and other network protocols for encryption, is the modern version of SSL. TLS
1.3 dropped support for older, less secure cryptographic features, and it
speeds up TLS handshakes, among other improvements.

The recipe below decrypts mesh mTLS by making the sidecar Envoy write its
per-session secrets to a keylog file. It only applies to **sidecar** workloads
(`swarm-sidecar-*`); ambient traffic is terminated by ztunnel, which has no
equivalent `EnvoyFilter` hook.

Setup a place to dump the crypto material:
```console
k --context kind-pasta-1 -n swarm-sidecar-n1 patch deployment peer --type merge -p '
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
k --context kind-pasta-1 apply -f - << EOF
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: peer
  namespace: swarm-sidecar-n1
spec:
  workloadSelector:
    labels:
      app: peer
  configPatches:
  - applyTo: CLUSTER
    match:
      context: SIDECAR_OUTBOUND
      cluster:
        service: "peer.swarm-sidecar-n2.svc.pasta.local"
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
k --context kind-pasta-1 -n swarm-sidecar-n1 exec -it deploy/peer -c istio-proxy -- \
  curl -X POST localhost:15000/quitquitquit
```

Optionally, use this command to list all available endpoints:
```console
istioctl --context kind-pasta-1 pc endpoint deploy/peer.swarm-sidecar-n1 | grep -E '^END|peer'
```

Start `tcpdump`:
```console
k --context kind-pasta-1 -n swarm-sidecar-n1 exec -it deploy/peer -c istio-proxy -- \
  sudo tcpdump -s0 -w /sniff/dump.pcap
```

Send a few requests to the endpoints listed above:
```console
k --context kind-pasta-1 -n swarm-sidecar-n1 exec -i deploy/peer -c manager -- \
  curl -s peer.swarm-sidecar-n2.svc.pasta.local/data | jq -r '.pod'
```

Stop `tcpdump` and download everything:
```console
k --context kind-pasta-1 -n swarm-sidecar-n1 cp -c istio-proxy peer-xxx:sniff ~/sniff
```

Open it with Wireshark:
```console
open ~/sniff/dump.pcap
```

Filter by `tls.handshake.type == 1` and follow the TLS stream of a `Client Hello` packet. 
Right click a `TLSv1.3` packet then `Protocol Preferences` --> `Transport Layer Security` --> `(Pre)-Master-Secret log filename` and provide the path to the `keylog` file.
