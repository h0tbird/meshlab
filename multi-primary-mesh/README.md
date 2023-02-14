# multi-primary-mesh

Multi-primary Istio mesh with a non-k8s workload running on a VM.
```bash
./bin/launch # Deploy the lab
./bin/delete # Destroy the lab
./bin/argocd # Print ArgoCD details
```

ArgoCD is used to deploy:
- https://github.com/h0tbird/istio
- https://github.com/h0tbird/httpbin

## Pull-through registries

A pull-through registry is a proxy that sits between your local Docker
installation and a remote Docker registry. It caches the images you pull from
the remote registry, and if another user on the same network tries to pull the
same image, the pull-through registry will serve it to them directly, rather
than pulling it again from the remote registry. The Container Runtime Interface
(CRI) in this demo is set up to use local pull-through registries for the
remote registries `docker.io`, `quay.io` and `ghcr.io` on each cluster.

<details><summary>Click me</summary><p>

List all images in a registry:
```console
curl -s 127.0.0.1:5001/v2/_catalog | jq # docker.io
curl -s 127.0.0.1:5002/v2/_catalog | jq # quay.io
curl -s 127.0.0.1:5003/v2/_catalog | jq # ghcr.io
```

List tags for a given image:
```console
curl -s 192.168.64.1:5002/v2/argoproj/argocd/tags/list | jq
```

Get the manifest for a given image and tag:
```console
curl -s http://192.168.64.1:5002/v2/argoproj/argocd/manifests/v2.4.7 | jq
```

</p></details>

## Step CLI

`step` is an easy-to-use CLI tool for building, operating, and automating
Public Key Infrastructure (PKI) systems and workflows. This demo uses `step`
as a standalone, general-purpose PKI toolkit: You can use it for many common
crypto and X.509 operations.

<details><summary>Click me</summary><p>

Print certificate or CSR details in human readable format:
```console
step certificate inspect --bundle tmp/istio-ca/root-cert.pem
```

</p></details>

## Multipass

Multipass from Canonical is a tool for launching, managing, and orchestrating
Linux virtual machines on local computers, simplifying the process for
development, testing, and other purposes. It provides a user-friendly
command-line interface and integrates with other tools for automation and
customization.

<details><summary>Click me</summary><p>

List all available instances:
```console
multipass list
```

Display information about all instances:
```console
multipass info --all
```

</p></details>

## Cloud-init

`cloud-init` is a tool used to configure virtual machine instances in the cloud
during their first boot. It simplifies the provisioning process, enabling quick
setup of new environments with desired configurations. The following commands
provide examples for monitoring and inspecting the cloud-init process on
various nodes in the system, including logs and scripts run during the
instance's first boot.

<details><summary>Click me</summary><p>

Tail the `cloud-init` logs:
```console
multipass exec kube-00 -- tail -f /var/log/cloud-init-output.log
multipass exec kube-01 -- tail -f /var/log/cloud-init-output.log
multipass exec kube-02 -- tail -f /var/log/cloud-init-output.log
```

Inspect the rendered `runcmd`:
```console
multipass exec kube-00 -- sudo cat /var/lib/cloud/instance/scripts/runcmd
multipass exec kube-01 -- sudo cat /var/lib/cloud/instance/scripts/runcmd
multipass exec kube-02 -- sudo cat /var/lib/cloud/instance/scripts/runcmd
multipass exec virt-01 -- sudo cat /var/lib/cloud/instance/scripts/runcmd
```

</p></details>

## Calico

Project Calico is an open-source networking solution for containerized
workloads that provides security, segmentation, and policy enforcement. It uses
IP tables and BGP routing to deliver a secure, scalable network fabric for
modern applications, integrating seamlessly with cloud-native platforms like
Kubernetes.

<details><summary>Click me</summary><p>

Get IP pool:
```console
calicoctl --context kube-01 get ipPool -o wide --allow-version-mismatch
calicoctl --context kube-02 get ipPool -o wide --allow-version-mismatch
```

Get node:
```console
calicoctl --context kube-01 get node -o wide --allow-version-mismatch
calicoctl --context kube-02 get node -o wide --allow-version-mismatch
```

</p></details>

## ArgoCD

ArgoCD is a GitOps platform for Kubernetes applications that enables continuous
delivery with declarative management and automation of deployments from Git
repositories to multiple clusters. With its user-friendly interface, robust
features, and deep Kubernetes integration, ArgoCD is a popular choice for
automating application delivery.

<details><summary>Click me</summary><p>

List all applications:
```console
argocd app list
```

Manually sync applications:
```console
argocd app sync kube-01-istio-base kube-02-istio-base
argocd app sync kube-01-istio-cni kube-02-istio-cni
argocd app sync kube-01-istio-pilot kube-02-istio-pilot
argocd app sync kube-01-istio-igws kube-02-istio-igws
argocd app sync kube-01-istio-ewgw kube-02-istio-ewgw
argocd app sync kube-01-httpbin kube-02-httpbin
```

</p></details>

## Istio

Istio is an open-source service mesh platform that provides traffic management,
policy enforcement, and telemetry collection for microservices applications. It
helps in improving the reliability, security, and observability of
service-to-service communication in a cloud-native environment. By integrating
with popular platforms such as Kubernetes, Istio makes it easier to manage the
complexities of microservices architecture.

<details><summary>Click me</summary><p>

Lists the remote clusters each `istiod` instance is connected to:
```console
istioctl --context kube-01 remote-clusters
```

Access the WebUI of `istiod`:
```console
istioctl --context kube-01 dashboard controlz deployment/istiod-1-16-2.istio-system
```

</p></details>

## Envoy

Envoy is an open-source proxy server designed for modern microservices
architectures, providing features such as load balancing, traffic management,
and service discovery. It runs standalone or integrated with a service mesh,
making it a powerful tool for microservices communication.

<details><summary>Click me</summary><p>

Inspect the `config_dump` of a VM:
```console
multipass exec virt-01 -- curl -s localhost:15000/config_dump | istioctl pc listeners --file -
multipass exec virt-01 -- curl -s localhost:15000/config_dump | istioctl pc routes --file -
multipass exec virt-01 -- curl -s localhost:15000/config_dump | istioctl pc clusters --file -
multipass exec virt-01 -- curl -s localhost:15000/config_dump | istioctl pc secret --file -
```

Set debug log level on a given proxy:
```console
istioctl pc log sleep-xxx.httpbin --level debug
k --context kube-01 -n httpbin logs -f sleep-xxx -c istio-proxy
```

Access the WebUI of a given envoy proxy:
```console
istioctl dashboard envoy sleep-xxx.httpbin
```

Dump the envoy config of an eastweast gateway:
```console
k --context kube-01 -n istio-system exec -it deployment/istio-eastwestgateway -- curl -s localhost:15000/config_dump
```

Dump the `common_tls_context` for a given envoy cluster:
```console
k --context kube-01 -n httpbin exec -i sleep-xxx -- \
curl -s localhost:15000/config_dump | jq '
  .configs[] |
  select(."@type"=="type.googleapis.com/envoy.admin.v3.ClustersConfigDump") |
  .dynamic_active_clusters[] |
  select(.cluster.name=="outbound|80||httpbin.httpbin.svc.cluster.local") |
  .cluster.transport_socket_matches[] |
  select(.name=="tlsMode-istio") |
  .transport_socket.typed_config.common_tls_context
'
```

List `LISTEN` ports:
```console
k --context kube-01 -n istio-system exec istio-eastwestgateway-xxx -- netstat -tuanp | grep LISTEN | sort -u
```

Check the status-port:
```console
curl -o /dev/null -Isw "%{http_code}" http://10.0.16.124:31123/healthz/ready
```

</p></details>

## TLS v1.3 troubleshooting

Setup a place to dump the crypto material:
```
k --context kube-01 -n httpbin patch deployment sleep --type merge -p '
spec:
  template:
    metadata:
      annotations:
        sidecar.istio.io/userVolume: "[{\"name\":\"sniff\", \"emptyDir\":{\"medium\":\"Memory\"}}]"
        sidecar.istio.io/userVolumeMount: "[{\"name\":\"sniff\", \"mountPath\":\"/sniff\"}]"
        proxy.istio.io/config: |
          proxyMetadata:
            OUTPUT_CERTS: /sniff
'
```

Write the required per-session TLS secrets to a file ([source](https://github.com/istio/istio/blob/5f90e4b9ae19800f4c539628ae038ec118835610/pilot/pkg/networking/core/v1alpha3/envoyfilter/cluster_patch_test.go#L241-L262)):
```
k --context kube-01 apply -f - << EOF
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: httpbin
  namespace: httpbin
spec:
  workloadSelector:
    labels:
      app: sleep
  configPatches:
  - applyTo: CLUSTER
    match:
      context: SIDECAR_OUTBOUND
      cluster:
        service: "httpbin.httpbin.svc.cluster.local"
        portNumber: 80
    patch:
      operation: MERGE
      value:
        transport_socket:
          name: "envoy.transport_sockets.tls"
          typed_config:
            "@type": "type.googleapis.com/envoy.extensions.transport_sockets.tls.v3.UpstreamTlsContext"
            common_tls_context:
              key_log:
                path: /sniff/keylog
EOF
```

Restart envoy to kill all TCP connections and force new TLS handshakes:
```
k --context kube-01 -n httpbin exec -it deployment/sleep -c istio-proxy -- curl -X POST localhost:15000/quitquitquit
```

Optionally, use this command to list all available endpoints:
```
istioctl --context kube-01 pc endpoint deploy/httpbin.httpbin | egrep '^END|httpbin'
```

Start `tcpdump`:
```
k --context kube-01 -n httpbin exec -it deployment/sleep -c istio-proxy -- sudo tcpdump -s0 -w /sniff/dump.pcap
```

Send a few requests to the endpoints listed above:
```
k --context kube-01 -n httpbin exec -i deployment/sleep -- curl -s httpbin/get | jq -r '.envs."HOSTNAME"'
```

Stop `tcpdump` and download everything:
```
k --context kube-01 -n httpbin cp -c istio-proxy sleep-xxx:sniff ~/sniff
```

Open it with Wireshark:
```
open ~/sniff/dump.pcap
```

Filter by `tls.handshake.type == 1` and follow the TLS stream of a `Client Hello` packet. 
Right click a `TLSv1.3` packet then `Protocol Preferences` --> `Transport Layer Security` --> `(Pre)-Master-Secret log filename` and provide the path to the `keylog` file.

## Testing

Send requests to service `httpbin`:
```
k --context kube-01 -n httpbin exec -i deployment/sleep -- curl -s httpbin/get | jq -r '.envs.HOSTNAME'
k --context kube-02 -n httpbin exec -i deployment/sleep -- curl -s httpbin/get | jq -r '.envs.HOSTNAME'
```

Same thing but using the VM:
```
for i in {1..20}; do multipass exec virt-01 -- curl -s httpbin/get | jq -r '.envs.HOSTNAME'; done | sort | uniq -c | sort -rn
```

## Certificates

Connect to the externally exposed `istiod` service and inspect the certificate bundle it presents:
```
step certificate inspect --bundle --servername istiod-1-16-2.istio-system.svc https://192.168.64.3:15012 --roots ./tmp/istio-ca/root-cert.pem
step certificate inspect --bundle --servername istiod-1-16-2.istio-system.svc https://192.168.64.3:15012 --insecure
```

As a client, inspect the certificate provided by a workload:
```
k -n httpbin exec -it deployment/sleep -c istio-proxy -- openssl s_client -showcerts httpbin:80
```

Get the spiffe ID for a given workload:
```
k --context kube-01 -n httpbin exec -it deployment/sleep -c istio-proxy -- cat /sniff/cert-chain.pem | step certificate inspect --bundle - | grep spiffe
```

## Workload endpoints

List all the endpoints for a given cluster and workload:
```
istioctl --context kube-01 pc endpoint deploy/httpbin.httpbin | egrep '^END|httpbin'
istioctl --context kube-02 pc endpoint deploy/httpbin.httpbin | egrep '^END|httpbin'
```

List all the metadata about a given endpoint IP:
```
k -n httpbin exec -it deployment/httpbin -c istio-proxy -- curl -X POST "localhost:15000/clusters" | grep '10.42.207.142'
```

## Devel

Provision only one VM:
```
source ./lib/misc.sh && launch_k8s kube-00
source ./lib/misc.sh && launch_vms virt-01
```

## Debug

Add locality info:
```
k --context kube-01 -n httpbin patch workloadentries httpbin-192.168.64.5-vm-network --type merge -p '{"spec":{"locality":"milky-way/solar-system/virt-01"}}'
k --context kube-01 -n httpbin patch deployment sleep --type merge -p '{"spec":{"template":{"metadata":{"labels":{"istio-locality":"milky-way.solar-system.kube-01"}}}}}'
k --context kube-01 -n httpbin label pod sleep-xxxx topology.istio.io/subzone=kube-01 topology.kubernetes.io/region=milky-way topology.kubernetes.io/zone=solar-system
```

```
k --context kube-01 -n httpbin patch deployment sleep --type merge -p '{"spec":{"template":{"metadata":{"labels":{
  "topology.kubernetes.io/region":"milky-way",
  "topology.kubernetes.io/zone":"solar-system",
  "topology.istio.io/subzone":"kube-01"
}}}}}'
```

Delete locality info:
```
k --context kube-01 -n httpbin patch workloadentries httpbin-192.168.64.5-vm-network --type json -p '[{"op": "remove", "path": "/spec/locality"}]'
k --context kube-01 -n httpbin patch deployment sleep --type json -p '[{"op": "remove", "path": "/spec/template/metadata/labels/istio-locality"}]'
k --context kube-01 -n httpbin label pod sleep-xxxx topology.istio.io/subzone- topology.kubernetes.io/region- topology.kubernetes.io/zone-
```

Set debug images:
```
k --context kube-01 -n istio-system set image deployment/istiod-1-16-2 discovery=docker.io/h0tbird/pilot:1.16.2
k --context kube-01 -n httpbin patch deployment sleep --type merge -p '{"spec":{"template":{"metadata":{"annotations":{"sidecar.istio.io/proxyImage":"docker.io/h0tbird/proxyv2:1.16.2"}}}}}'
```

Unset debug images:
```
k --context kube-01 -n istio-system set image deployment/istiod-1-16-2 discovery=docker.io/istio/pilot:1.16.2
k --context kube-01 -n httpbin patch deployment sleep --type merge -p '{"spec":{"template":{"metadata":{"annotations":{"sidecar.istio.io/proxyImage":"docker.io/istio/proxyv2:1.16.2"}}}}}'
```

Debug:
```
k --context kube-01 -n httpbin exec -it deployments/sleep -c istio-proxy -- sudo bash -c 'echo 0 > /proc/sys/kernel/yama/ptrace_scope'
k --context kube-01 -n istio-system exec -it deployments/istiod-1-16-2 -- dlv dap --listen=:40000 --log=true
k --context kube-01 -n istio-system port-forward deployments/istiod-1-16-2 40000:40000
```
