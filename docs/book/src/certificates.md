# Certificates

The trust chain of the lab is: a single `mesh` root CA in
[Vault](./components/vault.md) → one intermediate CA per cluster, issued by
[cert-manager](./components/cert-manager.md) into the `cacerts` secret → the
workload certificates istiod mints, with a per-cell trust domain
(`spiffe://pasta.local/...`).

Find below a collection of commands to troubleshoot certificate issues.

Inspect the root CA:
```console
curl -s http://127.0.0.1:8082/v1/mesh/ca/pem | step certificate inspect
```

Inspect a cluster's intermediate CA bundle:
```console
k --context kind-pasta-1 -n istio-system get secret cacerts \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | step certificate inspect --bundle
```

Connect to `istiod` and inspect the certificate bundle it presents (`15012` is
the mTLS xDS/CA port):
```console
k --context kind-pasta-1 -n istio-system port-forward svc/istiod-1-31-0-alpha-2 15012:15012 &
step certificate inspect --bundle --insecure \
  --servername istiod-1-31-0-alpha-2.istio-system.svc https://127.0.0.1:15012
```

Inspect the certificate chain of a given workload:
```console
istioctl --context kind-pasta-1 pc secret deploy/peer.swarm-sidecar-n1 -o json |
  jq -r '.dynamicActiveSecrets[] | select(.name=="default") |
         .secret.tlsCertificate.certificateChain.inlineBytes' |
  base64 -d | step certificate inspect --bundle
```

Inspect the root CA a workload trusts:
```console
istioctl --context kind-pasta-1 pc secret deploy/peer.swarm-sidecar-n1 -o json |
  jq -r '.dynamicActiveSecrets[] | select(.name=="ROOTCA") |
         .secret.validationContext.trustedCa.inlineBytes' |
  base64 -d | step certificate inspect --bundle
```

Same, but as a client from inside the proxy:
```console
k --context kind-pasta-1 -n swarm-sidecar-n1 exec -it deploy/peer -c istio-proxy -- \
  openssl s_client -showcerts peer.swarm-ambient-n1.svc.pasta.local:80
```

Follow a cert-manager issuance:
```console
k --context kind-pasta-1 -n istio-system get certificate,certificaterequest
k --context kind-pasta-1 -n istio-system describe certificate istio-cluster-ica
```
