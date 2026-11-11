# Istio 1.32 assessment for MeshLab

Investigated on 2026-11-11 against the running `pasta` cell.

## Recommendation

1. Consolidate the two east-west gateways into one per cluster. This was tested
   live and preserved the existing connectivity matrix. It reduces deployment
   overhead, but does not fix cross-network ambient/sidecar interoperability.
2. Adopt `PILOT_DISABLE_SELF_SIGNED_CA=true` as a separate hardening change.
   This lab intentionally uses a plugged-in CA; silently creating a different
  trust root is undesirable. Bootstrap ordering, upstream negative tests, and
  a live positive startup test have now passed. The flag is now configured for
  subsequent bootstraps in both dataplane modes.
3. Native histograms are feasible through the merger and existing collector and
  Prometheus versions. They are now the default and deployed on both pasta
  node collectors, accepting the metrics contract break. Kiali 2.34.1's
  histogram consumers need updating; the deployed Grafana dashboards do not.
4. Keep the new waypoint TLS/PROXY HTTP metrics flag as a targeted experiment.
   It programmed correctly, but the current HTTP workload did not demonstrate
   additional metric coverage in the short test.

The initial investigation rolled back both experiments. The subsequent requested
configuration changes are recorded below; the experimental waypoint telemetry
flag remains disabled.

## Implemented follow-up

During the initial follow-up, the lab configuration and running `pasta` clusters
were switched to the single
[gateway template](../charts/ewgw/templates/gateway.yaml), preserving sidecar-only
and single-network modes. The replacement gateways were verified ready with both
Envoy listeners before the old Gateways were removed.

The [node collector](../charts/otel-collector/templates/applicationsets/otelco-node.yaml)
now scrapes the annotated metrics merger endpoint, normally port 15020, instead
of directly scraping Envoy on 15090. It retains the `envoy` job name, one
discovery target per proxy, and the worker histogram relabeling. Ztunnel scraping
is unchanged. Live endpoint probes covered native sidecars, waypoints, and both
gateway types. The deployed OTel 0.163.2 binary validated the updated config;
the ApplicationSet was updated and both node collectors synced through Argo CD.
Prometheus now receives `istio_agent_scrape_format_total` from port 15020.

After rollout samples settled, Prometheus reported seven fresh `up` series per
cluster, all equal to 1 and all on port 15020, with no duplicate active targets
per proxy pod and no fresh port-15090 targets. Both collector Applications were
`Synced` and `Healthy`. Fresh peer logs after gateway cutover retained the 48/64
connectivity baseline. Helm checks covered ambient and sidecar gateway rendering
and confirmed the east-west ApplicationSet stays absent in single-network mode.

This adds agent metrics and any configured application metrics without collecting
Envoy metrics twice. It does not by itself enable native histograms end to end;
scrape protocol preferences and the histogram storage path were left unchanged.

The gateway Applications still source Git `HEAD`. At that rollout they remained
out of sync with Git; syncing the old Git revision could recreate the separate
gateways. The changes were subsequently committed and pushed in
[PR #97](https://github.com/h0tbird/meshlab/pull/97). The redeployment outcome is
recorded below.

## Configuration for subsequent bootstraps

The [istiod ApplicationSet](../charts/istio/templates/applicationsets/istio-istiod.yaml)
now sets `PILOT_DISABLE_SELF_SIGNED_CA: "true"` by default in both ambient and
sidecar mode, for single- and multi-network deployments. The existing bootstrap
dependency on healthy issuers is retained. A missing signing bundle deliberately
blocks startup rather than silently creating a different trust root.

Native histograms are enabled by default in both the collector chart and the
bootstrap environment fallback. `OTEL_NATIVE_HISTOGRAMS=false` explicitly
selects classic scraping for a subsequent bootstrap. The native configuration
uses the tested protobuf protocol and query parameters, with a default bucket
budget of 20. Worker histogram relabeling handles both classic suffixes and
native names without losing the worker label. An additional probe confirmed
that Envoy's native-mode response does not also carry its classic buckets. Enabling
`always_scrape_classic_histograms` cannot recover buckets absent from the
response. See the [observability guide](book/src/components/observability.md)
for rollback instructions and consumer query migrations.

The unified gateway and merger scraping changes remain in the configuration.
The gateway Application still reads the remote repository's `HEAD`, so the
unified gateway chart must be merged there before a default bootstrap can fetch
it. A local checkout or a pushed PR branch alone is insufficient. The istiod
and collector ApplicationSets are rendered locally and pick up the changes
above directly.

No optional waypoint telemetry, retry, outlier-ejection, or route-authorization
flags were enabled. The token-rotation memory concern is not a configuration
fix. The CA change remains for the next bootstrap; the native-histogram
collector change was subsequently deployed live as described below.

Validation covered all four istiod mode combinations, both collector histogram
modes rendered through the upstream chart and validated by OTel 0.163.2, shell
syntax, and 17 worker/unrelated-metric relabeling cases.

## Follow-up after redeployment

The recreated lab still had separate ambient and sidecar gateways in both
clusters. Its gateway Applications were `Synced` and `Healthy` against Git
`HEAD`, not the PR branch. Publishing the branch alone does not change that
source. The collector Applications did retain the merger scrape configuration.
This investigation left the recreated gateway topology unchanged.

### Fail-closed CA startup: validated

The [bootstrap DAG](../bin/meshlab) makes `istio-istiod` depend on both
`istio-base` and `istio-issuers`. The referenced
[sync workflow](../charts/wftemplates/templates/argocd-sync-and-wait.yaml) waits
for application health. In the observed recreation, the pasta-1 CA Certificate
was Ready at 11:08:05 UTC and the istiod Deployment was created at 11:08:13 UTC.

The existing upstream tests passed:

```sh
go test ./pilot/pkg/bootstrap -run '^TestCreateIstioCADisableSelfSignedCA' -count=1
```

These cover accepting plugged-in certificates, rejecting absent or incomplete
bundles, and refusing to generate or reuse the self-signed Kubernetes CA secret
when the flag is enabled. Negative cases ran against temporary files and fake
Kubernetes clients, not the live trust chain.

On pasta-1, setting `PILOT_DISABLE_SELF_SIGNED_CA=true` restarted istiod
successfully. Logs confirmed loading the existing `kubernetes.io/tls` signing
bundle and root from `etc/cacerts/ca.crt`. The root fingerprint was unchanged,
proxies reconnected, and connectivity remained 48/64. The flag was then removed
and the original configuration rolled out successfully.

This is suitable for the lab's permanent istiod environment settings, now
configured for the next bootstrap as described above. The
intentional tradeoff is that a missing CA bundle blocks control-plane startup
instead of creating a different root. A complete cold bootstrap with the flag
enabled was not run; the existing dependency ordering and live restart were
validated separately.

### Native histograms: end-to-end feasibility validated

Protobuf negotiation alone did not enable native histograms. A decoded
`swarm-ambient-n1` waypoint merger response contained 274 metric families and
24 histogram metrics, all classic. Adding Envoy's documented query parameters
produced 23 native histogram metrics; the remaining agent histogram stayed
classic.

The tested scrape settings were:

```yaml
metrics_path: /stats/prometheus
scrape_protocols: [PrometheusProto, PrometheusText0.0.4]
scrape_native_histograms: true
params:
  histogram_buckets: [prometheusnative]
  native_histogram_max_buckets: ["20"]
```

The merger forwards these parameters to Envoy. A temporary OTel 0.163.2
collector scraped one waypoint on port 15020 and remote-wrote request-latency
histograms to the existing Prometheus 3.16.0 instance. Its configuration passed
validation using the deployed collector binary. A dedicated job, metric prefix
`istio132_probe_`, and experiment label isolated the data from normal queries.
During this isolated probe, no production collector or Prometheus configuration
was changed.

Prometheus returned four series for this executed query:

```promql
histogram_count(istio132_probe_istio_request_duration_milliseconds{
  experiment="istio132-native-histograms"
})
```

Each returned a count of 112 at the sampled instant. This validates native
histogram production, merger preservation, collector conversion/export, and
Prometheus ingestion/querying for this path. The equivalent classic endpoint
exposed 88 request-latency series versus four native series. That is a series
count comparison, not a byte-storage, accuracy, CPU, or performance benchmark.

The initial recommendation was an opt-in migration; the lab owner subsequently
accepted the contract break and requested native histograms by default.
Consumers using `_bucket`, `_sum`, or `_count` series need new queries.
The selected bucket budget also needs accuracy evaluation. This experiment
covered one waypoint, not every sidecar/application combination; a merged text
application endpoint can still affect format negotiation. The temporary
collector Pod and ConfigMap were deleted. Its prefixed samples remain in
Prometheus history until normal retention removes them.

### Native histograms: default and live rollout

On 2026-11-11, the native-enabled node collector ApplicationSet was applied
locally and `pasta-1-otelco-node` and `pasta-2-otelco-node` were explicitly synced
through Argo CD. Both operations succeeded at approximately 11:32 UTC; both
Applications were `Synced`/`Healthy`, and each DaemonSet had its single desired
pod updated and Ready. The active ConfigMaps contained the tested settings
above. No gateway, istiod, ztunnel, or cluster collector configuration was
changed by this rollout.

Prometheus reported 36 native request-latency series per cluster under the
normal `istio_request_duration_milliseconds` name, not the probe prefix. Native
`histogram_quantile` and `histogram_avg` queries over one-minute rates returned
results for both clusters. A 30-second freshness check confirmed all 36 native
latency histograms per cluster and no fresh classic latency buckets. Each
cluster had eight fresh Envoy `up` series, all equal to 1 on port 15020, with
at most one target per proxy pod. Old classic samples remain in history and may be
visible during lookback/range windows; their presence alone does not prove
continued classic ingestion.

Consumer audit:

- **Kiali 2.34.1 needs changes.** Its `buildHistogramQueries` function in
  `prometheus/metrics.go` uses `_bucket` for quantiles and `_sum / _count` for
  averages. Latency and request/response-size charts depend on this builder.
  `graph/telemetry/istio/appender/response_time.go` separately hardcodes classic
  latency metrics for graph averages and percentiles. The inspected release
  configuration exposes no native-histogram switch. Counter-based traffic and
  error queries are unaffected; histogram displays can become empty as classic
  samples age out. Updating Kiali's implementation is a separate follow-up.
  A live one-minute metrics request for pasta-1's `swarm-sidecar-n1/peer`
  workload confirmed populated `request_count` and TCP metrics but null
  `request_duration_millis`, `request_size`, and `response_size`. The API uses
  `/kiali/api/namespaces/swarm-sidecar-n1/workloads/peer/metrics` with
  `clusterName=pasta-1`.
- **Neither deployed Grafana dashboard needs changes.** `Memory leak`
  (`adtlb8r`) uses counters/gauges. `MeshLab - Istio Control Plane Dashboard`
  (`123`) uses classic histograms only for `pilot_xds_config_size_bytes` and
  `pilot_xds_push_time`, both from the unchanged istiod scrape. Live panel
  queries were checked, not just repository JSON.
- **No recording/alerting rules were returned** by the live Prometheus and
  Grafana inventories. No compatibility rules or duplicate classic scrapes
  were added.

The [observability guide](book/src/components/observability.md#consumer-migration)
contains the executed native query patterns and rollback setting. Native
quantiles use the base metric without `le` grouping; averages use
`histogram_avg`, retaining the consumer's original filters and grouping.
This verifies ingestion and query behavior, not storage savings or percentile
accuracy under a representative load.

### Remote-cluster lifecycle: memory concern remains

A bounded run of [the existing benchmark](../bin/retoken) rotated pasta-1's
pasta-2 remote credential 40 times, every two seconds, sampling every five
rotations. Profiling was disabled during the loop, but the benchmark still
requests a GC before every sample. The original credential was held privately
and restored byte-for-byte afterward, rather than leaving a short-lived test
token installed. The run lasted 83 seconds without an istiod restart.

| Measurement | Before | After | Tail slope per rotation |
|---|---|---|---|
| Goroutines | 1,783 | 1,805 | +0.9 |
| Heap in use | 43.5 MiB | 144.8 MiB | +2.11 MiB |
| RSS | 146.1 MiB | 260.8 MiB | Not calculated |

A separate successful forced GC at 11:20:23 UTC still left 149,716,992 bytes
(about 142.8 MiB) of heap in use and 1,793 goroutines. The sampled in-use profile
contained about 107.7 MiB, led by approximately 50 MiB allocated by Kubernetes
`ObjectMeta.Unmarshal`. Allocation sites do not identify the retaining owner.

The lifecycle fixes are present, and goroutine growth is far below the older
reported +30.8 per rotation, but this run does **not** justify claiming the
memory issue is fixed. Retained heap warrants a longer plateau test and
retention analysis. There was no matched 1.31.4 baseline in this investigation.
Evidence remains in `/tmp/retoken-20261111T111812Z/metrics.csv` and
`/tmp/istio132-retoken-post-gc.pb.gz` in this devcontainer.

After restoration, both remote-cluster entries were `synced`, istiod was Ready,
and the final 60-second connectivity window retained the 48/64 baseline. The
temporary debug port-forward was stopped. No source or credential changes were
left by the benchmark; the measured istiod process was left running for further
inspection.

### Other controls: tests passed, targeted use only

Focused upstream tests passed for outlier error-code matchers and failure
percentage thresholds, sidecar inbound retry policy, and root-namespace
ProxyConfig selectors and precedence:

```sh
go test ./pilot/pkg/networking/core ./pilot/pkg/model \
  -run '^(TestApplyOutlierDetection.*|TestInboundHTTPRouteConfig|TestEffectiveProxyConfig|TestRootNamespaceWorkloadSelectors)$' \
  -count=1
```

These validate configuration generation, not ejection under load or an
end-to-end failure-recovery benefit. One important scope distinction:
`defaultInboundHttpRetryPolicy: {}` disables sidecar inbound retries, but
waypoints ignore that setting. It is not a mesh-wide ambient retry switch.
Root-namespace selectors work across namespaces, with workload-namespace
settings taking precedence, but no current duplicated configuration needs
migration. Keep these controls for directed experiments.

## Environment and release attribution

- Previous chart version: 1.31.4, from repository history.
- Current proxy images and istioctl: 1.32.0.
- Tilt-built istiod reports `1.32-dev`, but its running build revision is
  `19cc19624069db78ce5c6940b7be94c540eecfb0`, status `Clean`, exactly tag `1.32.0`.
- Both workload clusters run Kubernetes v1.37.0, within the documented 1.32
  support range of Kubernetes 1.33-1.37.
- Ambient and sidecar peers coexist across networks `pasta-1` and `pasta-2`.
- `AMBIENT_ENABLE_MULTI_NETWORK=true` and `AMBIENT_ENABLE_BAGGAGE=true` are
  already configured in the
  [istiod ApplicationSet](../charts/istio/templates/applicationsets/istio-istiod.yaml).

An important qualification: shared ambient/sidecar gateways were also backported
to **1.31.4**. Commit `f3423cddfb` (#62568) is an ancestor of 1.31.4, but not
1.31.0 through 1.31.3. The 1.32 equivalent is `6f6f40ea0e` (#62565).
The feature is advertised in the 1.32 announcement, but the lab could already
have adopted it on its previous patch version.

## Shared east-west gateway

### Configuration tested

One Gateway, Deployment, and LoadBalancer Service per cluster, using
`gatewayClassName: istio-east-west`. The tested pasta-1 resource was:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: istio-eastwestgateway
  namespace: istio-system
  labels:
    topology.istio.io/network: pasta-1
spec:
  gatewayClassName: istio-east-west
  listeners:
  - name: mesh
    port: 15008
    protocol: HBONE
    tls:
      mode: Terminate
      options:
        gateway.istio.io/tls-terminate-mode: ISTIO_MUTUAL
  - name: cross-network
    hostname: "*.local"
    port: 15443
    protocol: TLS
    tls:
      mode: Passthrough
```

Use network `pasta-2` in the other cluster. Both listeners were `Accepted` and
`Programmed`. Envoy had `connect_terminate` on 15008 and `0.0.0.0_15443` with
45 SNI filter chains. The generated Service exposed both ports plus health port
15021. No TLSRoute was needed for AUTO_PASSTHROUGH.

For a nonstandard sidecar port, the release notes specify
`gateway.istio.io/listener-protocol: auto-passthrough` in the listener TLS options.
The standard 15443 port and network label used here need no such override.

The code change is more than relaxing listener validation: istiod now builds
SNI-DNAT outbound clusters for ambient east-west gateways and includes these
gateways in Gateway-triggered CDS/LDS push handling. Merely accepting a TLS
listener in older releases did not establish equivalent behavior.

### Live results

The shared gateways were created at approximately 10:42 UTC. The original two
Gateways per cluster were backed up, then deleted; isolation began at
10:43:21 UTC. The old gateway pods were confirmed absent. The original topology
was restored and the experimental Gateways removed at 10:45:20 UTC.

The existing [matrix generator](../.github/skills/connectivity-matrix/gen-matrix.sh)
was run before, during, and after the experiment. During the isolated test its
kubectl log calls were given `--since-time`, including a second window beginning
at 10:44:15 UTC, so old successful requests could not contaminate the result.

| Path | Separate gateways | Shared gateway | Restored topology |
|---|---|---|---|
| Same cluster, any mode combination | Works | Works | Works |
| Cross-cluster ambient to ambient | Works | Works | Works |
| Cross-cluster sidecar to sidecar | Works | Works | Works |
| Cross-cluster ambient to sidecar | No observed success | No observed success | No observed success |
| Cross-cluster sidecar to ambient | No observed success | No observed success | No observed success |
| Successful matrix intersections | 48/64 | 48/64 | 48/64 |

These are short functional checks, not a sustained load test or a zero-downtime
claim. Each matrix cell means at least one successful observed hop. Consolidation
does not make the remaining 16 pairs work; the previously documented
[cross-mode problem](issues/cross-mode-cross-cluster-connectivity.md) remains
observable in this 1.32 lab.

Removing one gateway per cluster saves two proxy pods and two LoadBalancer
Services across the cell. The removed pods each request 100m CPU and 128Mi
memory: **200m CPU and 256Mi memory of aggregate scheduling requests**, not a
measurement of actual CPU or RSS savings. Both traffic classes will share the
remaining gateway's resource limits and failure domain.

### Permanent migration checklist

- Replace the two templates in [charts/ewgw](../charts/ewgw) with a single
  `istio-eastwestgateway` resource.
- In ambient mode, use `istio-east-west` and both listeners above.
- Preserve sidecar-only mode: use class `istio` and only TLS/15443 when
  `dataplaneMode=sidecar`; that mode does not enable ambient multi-network.
- Preserve single-network mode: the
  [east-west ApplicationSet](../charts/istio/templates/applicationsets/istio-ewgw.yaml)
  already omits the chart when `networkMode=single`.
- Update the chart values description and historical assumptions that the
  `istio-east-west` class cannot serve sidecar AUTO_PASSTHROUGH.
- Create and verify the replacement before pruning the old Gateways. A Helm
  template rename alone is not a migration or readiness guarantee.
- Coordinate the Git change with Argo CD: these Applications source Git `HEAD`,
  not the local checkout, and currently have no automated sync policy.
- Check listeners, remote endpoint discovery, and fresh-window connectivity
  after pruning. Keep the old manifests available for rollback.

## Other useful changes

| Feature | Fit for this lab | Recommendation |
|---|---|---|
| `PILOT_DISABLE_SELF_SIGNED_CA` | The [CA Certificate](../charts/issuers/templates/certificates/istio-cluster-ica.yaml) issues `cacerts` through `vault-ica`; the live Secret is present | Recommend adopting. Bootstrap ordering, isolated negative tests, and a live positive startup test passed. The temporary flag was removed afterward; see the follow-up above. |
| Remote-cluster lifecycle fixes | Directly relevant to [retoken experiments](issues/istiod-retoken-memory-leak-fix.md) | Already included. The 1.31.4-to-1.32.0 range contains handler-removal, nested collection swap, and KRT registration-leak fixes (`6bdfeade02`, `b348ea0cd2`, `1a22e33fce`). The new 40-rotation smoke test showed low goroutine growth but substantial retained-heap growth; see the follow-up above. |
| Reduced configuration pushes | Argo CD and certificate controllers generate metadata/config updates | Already included. Metadata-only EndpointSlice and unchanged Istio-label updates avoid unnecessary pushes (`386e5c1616`, `06bdf457ff`). Do not claim a CPU reduction without a before/after benchmark. |
| Kubernetes client deadlines | A stalled remote API can otherwise stall mesh controllers | Keep defaults: 90s response-header timeout and 15m unbounded-request timeout. Monitor `kube_client_deadline_fired_total` when emitted; do not disable timeouts preemptively. |
| HTTPRoute-targeted authorization | Useful for a future route-isolation exercise | Experimental, ingress only, enabled by `ENABLE_GATEWAY_API_HTTPROUTE_AUTH=true`. Not a replacement for waypoint service policies. Route ALLOW widens access alongside gateway ALLOW; DENY is additive. Enabling also changes the ingress ALLOW filter name to `istio.authorization.allow`, affecting EnvoyFilter matches. |
| Outlier detection extensions | Useful for deliberate fault-injection exercises | Test `outlierDetectionHttpErrorCodes` and `failurePercentageThreshold` against controlled error responses. Do not mask the current cross-mode failures by enabling ejection globally. |
| `defaultInboundHttpRetryPolicy` | Useful when measuring sidecar error behavior | `{}` disables the previously hardcoded sidecar inbound retries. Waypoints ignore this setting. Leave the default until a specific experiment needs it. |
| Root-namespace selector ProxyConfig | Could centralize matching proxy settings across swarm namespaces | Useful when shared settings are introduced; workload-namespace configuration takes precedence. No immediate migration demonstrated. |

### Waypoint HTTP metrics experiment

`AMBIENT_ENABLE_TLS_PROXY_HTTP_METRICS` is new relative to 1.31.4 and defaults
false. It enables TLS filter-state exchange for HTTP metrics over cross-cluster
TLS/PROXY paths. The lab already enables its multi-network and baggage context.

The flag was temporarily enabled on both istiod Deployments. After proxies
reconnected to xDS, both sampled `swarm-ambient-n1` waypoints gained two
`set_tls_filter_exchange` filters (previously zero). Istiod rollout readiness
preceded proxy reconnection, so an immediate config dump initially still showed
zero. The connectivity matrix remained 48/64.

The following live query was executed before and after the opt-in:

```promql
sum by (reporter, k8s_cluster_name, source_cluster, destination_cluster) (
  rate(istio_requests_total{
    k8s_deployment_name="waypoint",
    source_workload="peer",
    destination_workload="peer"
  }[1m])
)
```

Both observations showed the same four cluster combinations, around one request
per second each, with `reporter="waypoint"` and source cluster equal to the
collecting cluster. Remote destinations were already represented before the
opt-in. Therefore this test validates configuration and basic compatibility,
**not additional telemetry coverage**. A directed TLS/PROXY workload and a
longer observation window are needed before recommending it as a default.
The flag was removed from both Deployments after the test.

### Lower-priority features

- Native histogram passthrough fixes the pilot-agent metrics merger. During the
  initial assessment the node collector scraped Envoy directly, bypassing it,
  and the new agent scrape counter was absent. The follow-up above switches to
  the merger and exposes that counter. The later isolated probe validated
  native histogram production and ingestion end to end; the requested default
  migration is now deployed. Kiali query migration and accuracy evaluation
  remain follow-ups.
- `backendUtilization` requires backend ORCA load reports; ordinary k-swarm HTTP
  traffic is not evidence that these exist. Defer until testing an ORCA backend.
- The headless TCP wildcard listener optimization targets large headless TCP
  services; the inspected peer Service is HTTP/80. No immediate benefit shown.
- Required JWT rules, gateway ALPN/ECDH tuning, XBackend, and agentgateway
  changes suit dedicated security/Gateway API scenarios, not automatic changes
  to this lab's current workload.

## Sources

- [Istio 1.32 announcement](https://istio.io/latest/news/releases/1.32.x/announcing-1.32/)
- [1.32 change notes](https://istio.io/latest/news/releases/1.32.x/announcing-1.32/change-notes/)
- [1.32 upgrade notes](https://istio.io/latest/news/releases/1.32.x/announcing-1.32/upgrade-notes/)
- [Shared gateway implementation, 1.32](https://github.com/istio/istio/commit/6f6f40ea0e3af8d0330cf2a316777b065e84a12f)
- [Shared gateway backport, 1.31](https://github.com/istio/istio/pull/62568)
- [Waypoint TLS metrics](https://github.com/istio/istio/pull/61772)
- [Envoy admin histogram formats](https://www.envoyproxy.io/docs/envoy/latest/operations/admin.html)
- [OTel Prometheus receiver native histograms](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/prometheusreceiver/README.md#prometheus-native-histograms)
- [OTel Prometheus remote-write exporter](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/exporter/prometheusremotewriteexporter/README.md)
- [Kiali 2.34.1 histogram query builder](https://github.com/kiali/kiali/blob/v2.34.1/prometheus/metrics.go)
- [Kiali 2.34.1 graph response times](https://github.com/kiali/kiali/blob/v2.34.1/graph/telemetry/istio/appender/response_time.go)
- [Prometheus histogram guidance: count/sum and quantiles](https://prometheus.io/docs/practices/histograms/)
- Local source comparison: `git diff 1.31.4 1.32.0` and ancestry checks against
  the 1.31.0-1.31.4 tags; live Gateway status, Envoy config dumps, build metadata,
  peer-log aggregation, and Prometheus queries.
