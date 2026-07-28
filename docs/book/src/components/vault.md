# Vault

[Vault](https://developer.hashicorp.com/vault) is the root of trust of the lab.
It runs in **dev mode** (unsealed, in-memory, root token `meshlab123`) in the
`vault` namespace of the manager cluster — good enough for a lab, obviously not
for anything else.

- UI: <http://127.0.0.1:8082> (token `meshlab123`)

## What lives in it

The `populate-vault` `WorkflowTemplate`
(`charts/wftemplates/templates/populate-vault.yaml`) bootstraps it as a DAG root
of the [bootstrap workflow](./argo-workflows.md):

1. Enables a PKI secrets engine at `mesh/` with a max lease TTL of `87600h`
   (10 years) and generates the **single root CA** shared by all cells,
   `common_name=mesh`.
2. Writes the `mesh-cert-manager` policy, allowing
   `mesh/root/sign-intermediate`, `mesh/intermediate/set-signed` and reads of
   the `mesh/roles/ica` role.
3. Enables the `approle` auth method and creates the `mesh-cert-manager`
   AppRole (non-expiring, unlimited uses) that
   [cert-manager](./cert-manager.md) uses to have per-cluster intermediate CAs
   signed.

Because the whole task is guarded by existence checks, re-running it is a
no-op:
```console
meshlab run bootstrap-dag
```

## Everyday commands

The `vault` CLI is not shipped in the dev container; use the HTTP API or a
shell in the pod:

```console
k --context kind-mnger-1 -n vault exec -it vault-0 -- \
  env VAULT_TOKEN=meshlab123 vault secrets list
k --context kind-mnger-1 -n vault exec -it vault-0 -- \
  env VAULT_TOKEN=meshlab123 vault read mesh/cert/ca
```

Fetch the root CA over the published port:
```console
curl -s http://127.0.0.1:8082/v1/mesh/ca/pem | step certificate inspect
```

> Dev mode means the entire PKI is lost when the pod restarts. cert-manager will
> then fail to renew the intermediate CAs until `populate-vault` runs again.
