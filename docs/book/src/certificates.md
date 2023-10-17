# Certificates

Find below a collection of commands to troubleshoot certificate issues.

Connect to the externally exposed `istiod` service and inspect the certificate bundle it presents:
```console
step certificate inspect --bundle --servername istiod-1-18-2.istio-system.svc https://192.168.65.3:15012 --roots /path/to/root-ca.pem
step certificate inspect --bundle --servername istiod-1-18-2.istio-system.svc https://192.168.65.3:15012 --insecure
```

Inspect the certificate chain provided by a given workload:
```console
istioctl --context pasta-1 pc secret httpbin-xxxxxxxxxx-yyyyy.httpbin -o json | jq -r '.dynamicActiveSecrets[] | select(.name=="default") | .secret.tlsCertificate.certificateChain.inlineBytes' | base64 -d | step certificate inspect --bundle
```

Inspect the certificate root CA present in a given workload:
```console
istioctl --context pasta-1 pc secret sleep-xxxxxxxxxx-yyyyy.httpbin -o json | jq -r '.dynamicActiveSecrets[] | select(.name=="ROOTCA") | .secret.validationContext.trustedCa.inlineBytes' | base64 -d | step certificate inspect --bundle
```

Similar as above but this time as a client:
```console
k --context pasta-1 -n httpbin exec -it deployment/sleep -c istio-proxy -- openssl s_client -showcerts httpbin:80
```

Get details about the status of a cert-manager managed certificate:
```console
cmctl --context pasta-1 --namespace applab-blau status certificate blau
```