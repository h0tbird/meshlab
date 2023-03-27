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
(CRI) in this lab is set up to use local pull-through registries for the
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

## k3s

K3s is a lightweight version of Kubernetes designed for resource-constrained
environments like IoT devices and edge computing. It requires fewer resources
and has additional features such as simplified installation and compatibility
with ARM architectures.

<details><summary>Click me</summary><p>

</p></details>

## Flannel

Flannel is a lightweight provider of layer 3 network fabric that implements the
Kubernetes Container Network Interface (CNI). Flannel allocates a subnet lease
to each host out of a larger, preconfigured address space. Packets are forwarded
using one of several backend mechanisms including VXLAN and `host-gw`.

<details><summary>Click me</summary><p>

CNI conf dir:
```console
ll /var/lib/rancher/k3s/agent/etc/cni/net.d
```

CNI bin dir:
```console
ll /var/lib/rancher/k3s/data/current/bin
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

## CoreDNS

CoreDNS is a flexible, extensible DNS server that can be easily configured to
provide custom DNS resolutions in Kubernetes clusters. It allows for dynamic
updates, service discovery, and integration with external data sources, making
it a popular choice for service discovery and network management in
cloud-native environments.

<details><summary>Click me</summary><p>

Create a DNS record for `httpbin.demo.com`:
```console
k --context kube-01 -n kube-system create configmap coredns-custom --from-literal=demo.server='demo.com {
  hosts {
    ttl 60
    192.168.64.3 httpbin.demo.com
    fallthrough
  }
}'
```

Create a DNS record for `httpbin.demo.com`:
```console
k --context kube-02 -n kube-system create configmap coredns-custom --from-literal=demo.server='demo.com {
  hosts {
    ttl 60
    192.168.64.4 httpbin.demo.com
    fallthrough
  }
}'
```

</p></details>

## Vault

Blah, blah, blah...

<details><summary>Click me</summary><p>

Blah, blah, blah...

</p></details>

## cert-manager

Cert-manager is an open-source software that helps automate the management and
issuance of TLS/SSL certificates in Kubernetes clusters. It integrates with
various certificate authorities (CAs) and can automatically renew certificates
before they expire, ensuring secure communication between services running in
the cluster.

<details><summary>Click me</summary><p>

This check attempts to perform a dry-run create of a cert-manager v1alpha2
`Certificate` resource in order to verify that CRDs are installed and all the
required webhooks are reachable by the K8S API server. We use v1alpha2 API to
ensure that the API server has also connected to the cert-manager conversion
webhook:
```console
cmctl check api --context kube-01
```

Get details about the current status of a cert-manager Certificate resource,
including information on related resources like `CertificateRequest` or `Order`:
```console
cmctl status certificate --context kube-01 --namespace istio-system istio-cluster-ica
cmctl status certificate --context kube-01 --namespace istio-system ingressgateway
```

Mark cert-manager `Certificate` resources for manual renewal:
```console
cmctl renew --context kube-01 --namespace istio-system istio-cluster-ica
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

Access the `istiod` WebUI:
```console
istioctl --context kube-01 dashboard controlz deployment/istiod-1-17-1.istio-system
```

</p></details>

## klipper-lb

`klipper-lb` uses a host port for each `Service` of type `LoadBalancer` and
sets up iptables to forward the request to the cluster IP. The regular k8s
scheduler will find a free host port. If there are no free host ports, the
`Service` will stay in pending. There is one `DaemonSet` per `Service` of type
`LoadBalancer` and each `Pod` has one container per exposed `Service` port.

<details><summary>Click me</summary><p>

List the containers fronting the exposed `argocd-server` ports:
```console
k --context kube-00 -n kube-system get ds -l svccontroller.k3s.cattle.io/svcname=argocd-server -o yaml | yq '.items[].spec.template.spec.containers[].name'
```

List the containers fronting the exposed `istio-eastwestgateway` ports:
```console
k --context kube-01 -n kube-system get ds -l svccontroller.k3s.cattle.io/svcname=istio-eastwestgateway -o yaml | yq '.items[].spec.template.spec.containers[].name'
```

List the containers fronting the exposed `istio-ingressgateway` ports:
```console
k --context kube-01 -n kube-system get ds -l svccontroller.k3s.cattle.io/svcname=istio-ingressgateway -o yaml | yq '.items[].spec.template.spec.containers[].name'
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

## Locality load balancing

Istio's Locality Load Balancing (LLB) is a feature that helps distribute
traffic across different geographic locations in a way that minimizes latency
and maximizes availability. It routes traffic to the closest available instance
of the service, reducing network hops and improving performance, while also
providing fault tolerance and resilience. LLB is important for managing
microservices architectures.

<details><summary>Click me</summary><p>

`httpbin` priority and weight from the point of view of the `istio-ingressgateway`:
```console
watch "istioctl --context kube-01 -n istio-system pc endpoint deploy/istio-ingressgateway | grep -E '^END|httpbin'; echo; k --context kube-01 -n istio-system exec -it deployment/istio-ingressgateway -- curl -X POST localhost:15000/clusters | grep '^outbound|80||httpbin' | grep -E 'zone|region|::priority|::weight' | sort | sed -e '/:zone:/s/$/\n/'"
```

`httpbin` workloads, priority and weight from the point of view of the `sleep` pod:
```console
 watch "k --context kube-01 -n httpbin get po -o wide; echo; istioctl --context kube-01 -n httpbin pc endpoint deploy/sleep | grep -E '^END|httpbin'; echo; k --context kube-01 -n httpbin exec -it deployment/sleep -c istio-proxy -- curl -X POST localhost:15000/clusters | grep '^outbound|80||httpbin' | grep -E 'zone|region|::priority|::weight' | sort | sed -e '/:zone:/s/$/\n/'"
```

`VM`: patch the `workloadentries` object with locality metadata (bug?):
```console
k --context kube-01 -n httpbin patch workloadentries httpbin-192.168.64.5-vm-network --type merge -p '{"spec":{"locality":"milky-way/solar-system/virt-01"}}'
```

`VM`: retrieve topology metadata, assigned priority and weight:
```console
multipass exec virt-01 -- curl -s localhost:15000/clusters | grep '^outbound|80||httpbin' | grep -E 'zone|region|::priority|::weight' | sort | sed -e '/:zone:/s/$/\n/'
```

</p></details>

## Testing

The tests in this section should validate all functionalities.

<details><summary>Click me</summary><p>

Send requests to service `httpbin`:
```console
k --context kube-01 -n httpbin exec -i deployment/sleep -- curl -s httpbin/get | jq -r '.envs.HOSTNAME'
k --context kube-02 -n httpbin exec -i deployment/sleep -- curl -s httpbin/get | jq -r '.envs.HOSTNAME'
```

Same thing but using the VM:
```console
for i in {1..20}; do multipass exec virt-01 -- curl -s httpbin/get | jq -r '.envs.HOSTNAME'; done | sort | uniq -c | sort -rn
```

</p></details>

## TLS 1.3

TLS 1.3 is the latest version of the TLS protocol. TLS, which is used by HTTPS
and other network protocols for encryption, is the modern version of SSL. TLS
1.3 dropped support for older, less secure cryptographic features, and it
speeds up TLS handshakes, among other improvements.

<details><summary>Click me</summary><p>

Setup a place to dump the crypto material:
```console
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
```console
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
```console
k --context kube-01 -n httpbin exec -it deployment/sleep -c istio-proxy -- curl -X POST localhost:15000/quitquitquit
```

Optionally, use this command to list all available endpoints:
```console
istioctl --context kube-01 pc endpoint deploy/httpbin.httpbin | egrep '^END|httpbin'
```

Start `tcpdump`:
```console
k --context kube-01 -n httpbin exec -it deployment/sleep -c istio-proxy -- sudo tcpdump -s0 -w /sniff/dump.pcap
```

Send a few requests to the endpoints listed above:
```console
k --context kube-01 -n httpbin exec -i deployment/sleep -- curl -s httpbin/get | jq -r '.envs."HOSTNAME"'
```

Stop `tcpdump` and download everything:
```console
k --context kube-01 -n httpbin cp -c istio-proxy sleep-xxx:sniff ~/sniff
```

Open it with Wireshark:
```console
open ~/sniff/dump.pcap
```

Filter by `tls.handshake.type == 1` and follow the TLS stream of a `Client Hello` packet. 
Right click a `TLSv1.3` packet then `Protocol Preferences` --> `Transport Layer Security` --> `(Pre)-Master-Secret log filename` and provide the path to the `keylog` file.

</p></details>

## Certificates

Find below a collection of commands to troubleshoot certificate issues.

<details><summary>Click me</summary><p>

Connect to the externally exposed `istiod` service and inspect the certificate bundle it presents:
```console
step certificate inspect --bundle --servername istiod-1-17-1.istio-system.svc https://192.168.64.3:15012 --roots /path/to/root-ca.pem
step certificate inspect --bundle --servername istiod-1-17-1.istio-system.svc https://192.168.64.3:15012 --insecure
```

Inspect the certificate chain provided by a given workload:
```console
istioctl --context kube-02 pc secret httpbin-xxxxxxxxxx-yyyyy.httpbin -o json | jq -r '.dynamicActiveSecrets[] | select(.name=="default") | .secret.tlsCertificate.certificateChain.inlineBytes' | base64 -d | step certificate inspect --bundle
```

Inspect the certificate root CA present in a given workload:
```console
istioctl --context kube-02 pc secret sleep-xxxxxxxxxx-yyyyy.httpbin -o json | jq -r '.dynamicActiveSecrets[] | select(.name=="ROOTCA") | .secret.validationContext.trustedCa.inlineBytes' | base64 -d | step certificate inspect --bundle
```

Similar as above but this time as a client:
```console
k --context kube-01 -n httpbin exec -it deployment/sleep -c istio-proxy -- openssl s_client -showcerts httpbin:80
```

</p></details>

## Devel

Provision only one VM:
```console
source ./lib/misc.sh && launch_k8s kube-00
source ./lib/misc.sh && launch_vms virt-01
```

## Debug

Add locality info:
```console
k --context kube-01 -n httpbin patch workloadentries httpbin-192.168.64.5-vm-network --type merge -p '{"spec":{"locality":"milky-way/solar-system/virt-01"}}'
k --context kube-01 -n httpbin patch deployment sleep --type merge -p '{"spec":{"template":{"metadata":{"labels":{"istio-locality":"milky-way.solar-system.kube-01"}}}}}'
k --context kube-01 -n httpbin label pod sleep-xxxx topology.istio.io/subzone=kube-01 topology.kubernetes.io/region=milky-way topology.kubernetes.io/zone=solar-system
```

```console
k --context kube-01 -n httpbin patch deployment sleep --type merge -p '{"spec":{"template":{"metadata":{"labels":{
  "topology.kubernetes.io/region":"milky-way",
  "topology.kubernetes.io/zone":"solar-system",
  "topology.istio.io/subzone":"kube-01"
}}}}}'
```

Delete locality info:
```console
k --context kube-01 -n httpbin patch workloadentries httpbin-192.168.64.5-vm-network --type json -p '[{"op": "remove", "path": "/spec/locality"}]'
k --context kube-01 -n httpbin patch deployment sleep --type json -p '[{"op": "remove", "path": "/spec/template/metadata/labels/istio-locality"}]'
k --context kube-01 -n httpbin label pod sleep-xxxx topology.istio.io/subzone- topology.kubernetes.io/region- topology.kubernetes.io/zone-
```

Set debug images:
```console
k --context kube-01 -n istio-system set image deployment/istiod-1-17-1 discovery=docker.io/h0tbird/pilot:1.17.1
k --context kube-01 -n httpbin patch deployment sleep --type merge -p '{"spec":{"template":{"metadata":{"annotations":{"sidecar.istio.io/proxyImage":"docker.io/h0tbird/proxyv2:1.17.1"}}}}}'
```

Unset debug images:
```console
k --context kube-01 -n istio-system set image deployment/istiod-1-17-1 discovery=docker.io/istio/pilot:1.17.1
k --context kube-01 -n httpbin patch deployment sleep --type merge -p '{"spec":{"template":{"metadata":{"annotations":{"sidecar.istio.io/proxyImage":"docker.io/istio/proxyv2:1.17.1"}}}}}'
```

Debug:
```console
k --context kube-01 -n httpbin exec -it deployments/sleep -c istio-proxy -- sudo bash -c 'echo 0 > /proc/sys/kernel/yama/ptrace_scope'
k --context kube-01 -n istio-system exec -it deployments/istiod-1-17-1 -- dlv dap --listen=:40000 --log=true
k --context kube-01 -n istio-system port-forward deployments/istiod-1-17-1 40000:40000
```
