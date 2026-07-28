# Observability

The observability stack is centralised on the manager cluster: metrics are
collected in every cluster by the OpenTelemetry Collector and shipped to a
single Prometheus, which Grafana and Kiali read from.

| Component                | Where            | Namespace    | URL                     |
| ------------------------ | ---------------- | ------------ | ----------------------- |
| Prometheus               | `mnger-1`        | `monitoring` | <http://127.0.0.1:8083> |
| Grafana                  | `mnger-1`        | `monitoring` | <http://127.0.0.1:8084> |
| Kiali (operator + CR)    | `mnger-1`        | `monitoring` | <http://127.0.0.1:8085> |
| `otelco-node` collector  | every cluster    | `monitoring` | —                       |
| `otelco-cluster` collector | every cluster  | `monitoring` | —                       |
| metrics-server           | every cluster    | `monitoring` | —                       |

## OpenTelemetry Collector

Two releases are deployed per cluster from `charts/otel-collector`:

- `otelco-node` — a **DaemonSet** that scrapes, on its own node only, the Envoy
  admin `/stats/prometheus` endpoint of every pod exposing a `*-envoy-prom`
  port (sidecars and gateways), the ztunnel pods (`ztunnel-stats` port), and the
  kubelet via the `kubeletstats` receiver.
- `otelco-cluster` — a **Deployment** that scrapes istiod on port 15014 and
  collects cluster-level metrics through the `k8sclusterreceiver` preset.

Both remote-write to the manager's Prometheus at
`http://prometheus.demo.lab/api/v1/write` (resolved via
[CoreDNS + k8s_gateway](./coredns.md)), and a `resource` processor stamps every
series with the `k8s.cluster.name` label — which is what makes the multi-cluster
dashboards possible.

Because the scrape configuration lives in the collectors, Prometheus itself
ships with an almost empty `scrape_configs`. That is expected, not a
misconfiguration.

> istiod is configured with an `otel-tracing` extension provider pointing at
> `otelco-cluster-opentelemetry-collector.monitoring.svc:4318`, but no
> `Telemetry` resource selects it and the collector's `traces` pipeline is
> disabled. Distributed tracing is therefore **wired but not collected** today;
> enabling it needs a `Telemetry` resource plus a `traces` pipeline in
> `charts/otel-collector`.

## Prometheus

Query the remote-written series:
```console
curl -s 'http://127.0.0.1:8083/api/v1/label/k8s_cluster_name/values' | jq
curl -sG http://127.0.0.1:8083/api/v1/query --data-urlencode 'query=istio_requests_total' | jq
```

## Grafana

Anonymous access is enabled with the `Viewer` role, so the UI opens without a
login; `admin` / `meshlab123` still works for editing.

Dashboards are **not** provisioned by default. The `grafana-git-sync` section
only runs when `GITHUB_TOKEN` is set, in which case Grafana syncs the dashboards
under `grafana/` in this repository. Without a token, an empty dashboard list is
the expected state.

## Kiali

Kiali is installed via its operator on the manager cluster and configured with
`auth.strategy: anonymous`, so the login page just needs the `Log In` button.
It reaches the workload clusters through the remote-cluster secrets created by
the `kiali-secrets` section (using upstream's
`kiali-prepare-remote-cluster.sh`), and it is configured to ignore its own home
cluster — there is no mesh on `mnger-1`.

If a cluster is missing from the Kiali mesh view, re-create the secrets and let
the operator reconcile:
```console
meshlab run kiali-secrets
k --context kind-mnger-1 -n monitoring get secrets
```
