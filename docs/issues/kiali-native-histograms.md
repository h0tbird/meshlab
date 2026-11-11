# Support native Prometheus histograms for Istio metrics

## Summary

Kiali's histogram queries assume that Istio metrics are stored as classic
Prometheus histograms. When Envoy is scraped in native-histogram mode, Kiali
continues to show request rates, but the tested workload metrics API returns
no latency or request/response-size data.

The native histograms are present in Prometheus and can be queried successfully
with native PromQL functions. Could Kiali support this representation for its
histogram charts and graph response-time calculations?

## Environment

Observed on 2026-11-11:

| Component | Version / configuration |
| --- | --- |
| Kiali server and operator | 2.34.1 |
| Istio proxies and charts | 1.32.0 |
| Istiod | Locally built from tag 1.32.0; reports 1.32-dev |
| OpenTelemetry Collector Contrib | 0.163.2 |
| Prometheus | 3.16.0 |
| Kubernetes | 1.37.0 |
| Mesh | Two clusters, with sidecar and ambient workloads |
| Collection path | Envoy -> pilot-agent metrics merger on port 15020 -> OTel Prometheus receiver -> remote write -> Prometheus |

The workload API reproduction below uses a sidecar workload. The environment
also contains waypoints and gateways, but this report does not claim that
every Kiali view or deployment mode was tested.

## Steps To Reproduce

1. Generate HTTP traffic to an Istio-injected workload and configure Kiali to
   use the Prometheus instance receiving its metrics.
2. Scrape the pilot-agent metrics merger with the following settings in the
   OTel Prometheus receiver's Envoy scrape job. Retain the existing target
   discovery configuration, pointing at port 15020:

   ```yaml
   metrics_path: /stats/prometheus
   scrape_interval: 15s
   scrape_protocols: [PrometheusProto, PrometheusText0.0.4]
   scrape_native_histograms: true
   params:
     histogram_buckets: [prometheusnative]
     native_histogram_max_buckets: ["20"]
   ```

3. Keep remote write to Prometheus enabled and verify that native histogram
   queries return results. Merely negotiating protobuf was not sufficient;
   the histogram parameters above were also needed in this setup.
4. Allow the previous classic samples to age out of the query's rate window.
   Old samples remain in Prometheus history and can temporarily mask the issue.
5. Request recent workload metrics from Kiali. In this lab, the request was:

   ```sh
   curl -fsS \
     'http://127.0.0.1:8085/kiali/api/namespaces/swarm-sidecar-n1/workloads/peer/metrics?clusterName=pasta-1&direction=inbound&duration=60&step=15&rateInterval=30s&avg=true&quantiles%5B%5D=0.95' \
     | jq '{request_count_series: (.request_count | length), request_duration_millis, request_size, response_size}'
   ```

   Substitute the Kiali URL, cluster, namespace, and workload for another
   installation. Supply authentication as required by that installation.

## Actual Behavior

The observed workload metrics response, reduced by the command above, was:

```json
{
  "request_count_series": 1,
  "request_duration_millis": null,
  "request_size": null,
  "response_size": null
}
```

Request-rate and TCP metrics remained populated. At the same time:

- Both node collector Applications were synced and healthy.
- All 16 Envoy scrape targets were healthy, with one active target per proxy.
- Prometheus contained 36 fresh native request-latency histograms per cluster.
- A 30-second freshness check found no fresh classic request-latency buckets.
- Native p95 and average latency queries returned results for both clusters.

Envoy's native-mode response in this setup did not include its classic buckets.
No parallel classic scrape or compatibility recording rules were installed.

## Expected Behavior

Kiali should calculate latency and request/response-size statistics from native
Istio histograms when that is the representation available in Prometheus.
Graph average and percentile response times should also support native data.
Existing classic-histogram installations should continue to work.

## Relevant Query Paths

In the inspected Kiali 2.34.1 source:

- [`buildHistogramQueries` in `prometheus/metrics.go`](https://github.com/kiali/kiali/blob/v2.34.1/prometheus/metrics.go)
  builds averages from `_sum / _count` and quantiles from `_bucket`, grouped
  with `le`.
- [`ResponseTimeAppender.appendGraph`](https://github.com/kiali/kiali/blob/v2.34.1/graph/telemetry/istio/appender/response_time.go)
  separately uses the classic request-duration metrics for graph averages and
  percentiles.

The graph impact is based on those query paths, not a separate graph UI test.
No native-histogram configuration switch was found in the inspected release.

## Native Query Equivalents

These queries succeeded against the same Prometheus instance while the Kiali
API returned no histogram data. They calculate destination-reported latency in
milliseconds. The `k8s_cluster_name` label and job naming are specific to this
lab's collector configuration:

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

A Kiali implementation would need to retain its existing reporter, namespace,
workload, service, and cluster selection semantics. The essential differences
are using the base histogram metric, removing `le` from native quantile
grouping, and using `histogram_avg` or `histogram_sum` / `histogram_count` for
averages. Request and response sizes need the equivalent treatment.

Detection versus explicit configuration, mixed classic/native deployments,
and historical queries spanning a migration would need a defined behavior.
This report does not prescribe a particular implementation.

## Workaround And Context

Reverting the Envoy scrape to classic histograms restores the representation
expected by Kiali's existing queries. Setting
`always_scrape_classic_histograms` cannot recover classic buckets that are
absent from the endpoint response.

Istio 1.32's metrics-merger native-histogram passthrough fix makes this
collection path usable without bypassing the merger. The ingestion path was
verified end to end; the remaining compatibility gap is in Kiali's queries.
This is not a claim that the behavior is a regression introduced in Kiali
2.34.1; earlier Kiali releases were not compared.

## References

- [Istio 1.32 change notes](https://istio.io/latest/news/releases/1.32.x/announcing-1.32/change-notes/)
- [Envoy admin histogram formats](https://www.envoyproxy.io/docs/envoy/latest/operations/admin.html)
- [Prometheus histogram guidance](https://prometheus.io/docs/practices/histograms/)
- [OTel Prometheus receiver native histogram support](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/prometheusreceiver/README.md#prometheus-native-histograms)