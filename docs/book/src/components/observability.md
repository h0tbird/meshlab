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

- `otelco-node` — a **DaemonSet** that scrapes, on its own node only, the Istio
  agent metrics merger at `/stats/prometheus` on port 15020 (sidecars, waypoints,
  and gateways), the ztunnel pods (`ztunnel-stats` port), and the kubelet via the
  `kubeletstats` receiver.
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

The `envoy` scrape job keeps one discovery target per proxy by selecting its
`*-envoy-prom` port, then uses the pod's `prometheus.io/port` and
`prometheus.io/path` annotations to reach the merger. Pods must advertise
`prometheus.io/scrape: "true"`. This also works for native sidecars that do not
declare port 15020 in their container spec. Envoy is not scraped a second time
on port 15090.

The merger preserves Envoy metrics and adds agent metrics, including
`istio_agent_scrape_format_total`. It also merges application metrics when
configured on an injected workload; it does not collect ambient applications'
metrics through ztunnel. The existing job name and worker histogram relabeling
are retained for both classic and native histogram names.

### Native histograms

Native Envoy histograms are enabled by default, both in the collector wrapper
chart (`nativeHistograms.enabled=true`) and during bootstrap. The `envoy` job
requests protobuf, enables native histogram ingestion, and
passes `histogram_buckets=prometheusnative` to the merger. The bucket budget is
controlled by the chart's `nativeHistograms.maxBuckets` value (default 20).
Ztunnel scraping, the separate istiod scrape, and the single-target-per-proxy
discovery rules are unchanged. Agent/application histograms are not forcibly
converted; this is an Envoy migration, not a conversion of every lab metric.

Both pasta node collectors were synced successfully with these settings on
2026-11-11. OTel 0.163.2 remote-writes native histograms to Prometheus 3.16.0.
Envoy's native-mode response omits its classic buckets: `_bucket`, `_sum`, and
`_count` queries must migrate to the base metric. No duplicate classic scrape
or compatibility recording rules are installed. Historical classic samples
remain queryable until retention expires and can briefly mask missing live
data. The bucket budget still needs workload-specific accuracy evaluation;
a merged application endpoint that only serves text can affect negotiation.

For a classic-histogram rollback on the next bootstrap:

```console
OTEL_NATIVE_HISTOGRAMS=false meshlab
```

Changing the environment alone does not update running collectors. Render/apply
the node collector ApplicationSet and sync its Applications to change the live
pipeline. Omitting the variable enables native histograms.

### Consumer migration

| Consumer | Impact and required action |
| --- | --- |
| Kiali 2.34.1 histogram charts | `prometheus/metrics.go`, `buildHistogramQueries`, builds classic quantiles and averages. Latency and request/response-size charts need native PromQL support in Kiali. |
| Kiali graph response times | `graph/telemetry/istio/appender/response_time.go` also hardcodes classic latency metrics. Both average and percentile edge labels need updating. Traffic rates and error ratios still use unaffected counters. |
| Grafana: Memory leak | No histogram queries; no migration needed. |
| Grafana: MeshLab - Istio Control Plane Dashboard | Its Push Size and Push Time panels use `pilot_*_bucket` metrics from the unchanged istiod scrape; no migration needed. |
| Recording and alerting rules | None were returned by the live Prometheus/Grafana rule inventories during the audit. Future Envoy histogram rules must use native queries. |

The audit covered both deployed Grafana dashboards and Kiali's exact release
source. No native-histogram configuration switch was found in Kiali 2.34.1;
this requires a server implementation change or a release with native support,
not an invented Helm value. Kiali has deliberately not been patched here.

These native queries were executed successfully against the live pipeline.
They calculate destination-reported latency in milliseconds, grouped by the
collecting cluster:

```promql
histogram_quantile(0.95,
  sum by (k8s_cluster_name) (
    rate(istio_request_duration_milliseconds{job=~".*/envoy",reporter="destination"}[1m])
  )
)

histogram_avg(
  sum by (k8s_cluster_name) (
    rate(istio_request_duration_milliseconds{job=~".*/envoy",reporter="destination"}[1m])
  )
)
```

When migrating consumers, retain their reporter/namespace/workload filters and
grouping labels, but remove `le` from native quantile aggregation. Replace
classic count/sum access with `histogram_count`/`histogram_sum` applied to the
native histogram (after `rate` when calculating rates). Apply the same pattern
to `istio_request_bytes`, `istio_response_bytes`, and Envoy histograms. Do not
sum source and destination reporters together as a count of unique requests.
See Prometheus's [histogram guidance](https://prometheus.io/docs/practices/histograms/),
especially "Count and sum of observations" and "Quantiles".

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
