# cert-manager

[cert-manager](https://cert-manager.io) automates the issuance and renewal of
X.509 certificates. In this lab it is deployed to **every** cluster and it is
the bridge between [Vault](./vault.md) and Istio: it turns the single `mesh`
root CA into one intermediate CA per cluster.

## The issuers

`charts/issuers` is synced into `istio-system` (as the `istio-issuers`
application) and contains:

| Resource | Kind | Purpose |
| -------- | ---- | ------- |
| `vault-ica-approle` | `Secret` | The AppRole `secretId` created by `populate-vault`. |
| `vault-ica` | `Issuer` | Vault issuer authenticating with that AppRole against `mesh/`. |
| `istio-cluster-ica` | `Certificate` | The cluster's intermediate CA (`isCA: true`, CN = cluster name, 5-year duration, renewed 1 year before expiry, key rotated on every renewal). It writes the `cacerts` secret that istiod consumes. |
| `ingress-ca` | `Issuer` / `ClusterIssuer` | CA issuer backed by `cacerts`, used for ingress/workload leaf certificates. |

istiod runs with `AUTO_RELOAD_PLUGIN_CERTS: true`, so a renewal of `cacerts` is
picked up without restarting the control plane.

## Everyday commands

The `cmctl` CLI is not installed in the dev container; use `kubectl`.

Check the intermediate CA of a cluster:
```console
k --context kind-pasta-1 -n istio-system get certificate istio-cluster-ica
k --context kind-pasta-1 -n istio-system describe certificate istio-cluster-ica
```

Follow the request chain when issuance is stuck:
```console
k --context kind-pasta-1 -n istio-system get certificaterequests
k --context kind-pasta-1 -n cert-manager logs -l app=cert-manager --tail 50
```

Inspect the resulting CA bundle:
```console
k --context kind-pasta-1 -n istio-system get secret cacerts \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | step certificate inspect --bundle
```

Force a reissue (there is no `cmctl` here, so delete the secret and let the
`Certificate` controller re-create it):
```console
k --context kind-pasta-1 -n istio-system delete secret cacerts
k --context kind-pasta-1 -n istio-system get certificate istio-cluster-ica -w
```
