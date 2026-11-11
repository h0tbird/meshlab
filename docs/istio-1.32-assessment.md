# Istio 1.32 assessment for MeshLab

Investigated on 2026-11-11 against the running `pasta` cell.

## Recommendation

1. Consolidate the two east-west gateways into one per cluster. This was tested
   live and preserved the existing connectivity matrix. It reduces deployment
   overhead, but does not fix cross-network ambient/sidecar interoperability.
2. Consider `PILOT_DISABLE_SELF_SIGNED_CA=true` as a separate hardening change.
   This lab intentionally uses a plugged-in CA; silently creating a different
   trust root is undesirable. Validate bootstrap ordering before enabling it.
3. Keep the new waypoint TLS/PROXY HTTP metrics flag as a targeted experiment.
   It programmed correctly, but the current HTTP workload did not demonstrate
   additional metric coverage in the short test.

The initial investigation rolled back both experiments. The subsequent requested
configuration changes are recorded below; the experimental waypoint telemetry
flag remains disabled.

## Implemented follow-up

The lab configuration and running `pasta` clusters now use the single
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

The gateway Applications still source Git `HEAD`. Until the chart changes are
published, they remain out of sync with Git; syncing the old Git revision can
recreate the separate gateways. No commits or pushes were made by this rollout.

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
| `PILOT_DISABLE_SELF_SIGNED_CA` | The [CA Certificate](../charts/issuers/templates/certificates/istio-cluster-ica.yaml) issues `cacerts` through `vault-ica`; the live Secret is present | High-value fail-closed hardening. Ensure certificate issuance precedes istiod readiness; test startup with and without the bundle separately. Not enabled in this investigation. |
| Remote-cluster lifecycle fixes | Directly relevant to [retoken experiments](issues/istiod-retoken-memory-leak-fix.md) | Already included. The 1.31.4-to-1.32.0 range contains handler-removal, nested collection swap, and KRT registration-leak fixes (`6bdfeade02`, `b348ea0cd2`, `1a22e33fce`). Repeat the existing rotation benchmark for quantitative evidence; no new leak benchmark was run here. |
| Reduced configuration pushes | Argo CD and certificate controllers generate metadata/config updates | Already included. Metadata-only EndpointSlice and unchanged Istio-label updates avoid unnecessary pushes (`386e5c1616`, `06bdf457ff`). Do not claim a CPU reduction without a before/after benchmark. |
| Kubernetes client deadlines | A stalled remote API can otherwise stall mesh controllers | Keep defaults: 90s response-header timeout and 15m unbounded-request timeout. Monitor `kube_client_deadline_fired_total` when emitted; do not disable timeouts preemptively. |
| HTTPRoute-targeted authorization | Useful for a future route-isolation exercise | Experimental, ingress only, enabled by `ENABLE_GATEWAY_API_HTTPROUTE_AUTH=true`. Not a replacement for waypoint service policies. Route ALLOW widens access alongside gateway ALLOW; DENY is additive. Enabling also changes the ingress ALLOW filter name to `istio.authorization.allow`, affecting EnvoyFilter matches. |
| Outlier detection extensions | Useful for deliberate fault-injection exercises | Test `outlierDetectionHttpErrorCodes` and `failurePercentageThreshold` against controlled error responses. Do not mask the current cross-mode failures by enabling ejection globally. |
| `defaultInboundHttpRetryPolicy` | Useful when measuring sidecar error behavior | `{}` disables the previously hardcoded inbound retries, making a useful experimental control. It changes behavior mesh-wide; leave the default until a specific experiment needs it. |
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
  the merger and exposes that counter. Protobuf negotiation, histogram
  production, OTel conversion/remote-write, and Prometheus storage still need
  validation before expecting native histogram benefits.
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
- Local source comparison: `git diff 1.31.4 1.32.0` and ancestry checks against
  the 1.31.0-1.31.4 tags; live Gateway status, Envoy config dumps, build metadata,
  peer-log aggregation, and Prometheus queries.
