# cert-manager

Cert-manager is an open-source software that helps automate the management and
issuance of TLS/SSL certificates in Kubernetes clusters. It integrates with
various certificate authorities (CAs) and can automatically renew certificates
before they expire, ensuring secure communication between services running in
the cluster.

Print the cert-manager CLI version and the deployed cert-manager version:
```
cmctl --context pasta-1 version
```

This check attempts to perform a dry-run create of a cert-manager v1alpha2
`Certificate` resource in order to verify that CRDs are installed and all the
required webhooks are reachable by the K8S API server. We use v1alpha2 API to
ensure that the API server has also connected to the cert-manager conversion
webhook:
```console
cmctl check api --context pasta-1
```

Get details about the current status of a cert-manager Certificate resource,
including information on related resources like `CertificateRequest` or `Order`:
```console
cmctl --context pasta-1 --namespace istio-system status certificate istio-cluster-ica
```

Mark cert-manager `Certificate` resources for manual renewal:
```console
cmctl renew --context pasta-1 --namespace istio-system istio-cluster-ica
```
