# it-works-on-my-machine
Multi-cluster Istio mesh with a non-k8s workload on a VM.

## Local pull-through registries

List images in pull-through registries:
```bash
curl -s 192.168.64.1:5001/v2/_catalog | jq # docker.io
curl -s 192.168.64.1:5002/v2/_catalog | jq # quay.io
curl -s 192.168.64.1:5003/v2/_catalog | jq # ghcr.io
```

List image tags in pull-through registries:
```
curl -s 192.168.64.1:5002/v2/argoproj/argocd/tags/list | jq
```

Get manifest for a given image tag:
```
curl -s http://192.168.64.1:5002/v2/argoproj/argocd/manifests/v2.4.7 | jq
```

## Cluid-init

Tail cloud-init logs:
```
multipass exec kube-00 -- tail -f /var/log/cloud-init-output.log
multipass exec kube-01 -- tail -f /var/log/cloud-init-output.log
multipass exec kube-02 -- tail -f /var/log/cloud-init-output.log
```

Inspect the rendered `runcmd`:
```
multipass exec kube-00 -- sudo cat /var/lib/cloud/instance/scripts/runcmd
multipass exec kube-01 -- sudo cat /var/lib/cloud/instance/scripts/runcmd
multipass exec kube-02 -- sudo cat /var/lib/cloud/instance/scripts/runcmd
multipass exec virt-01 -- sudo cat /var/lib/cloud/instance/scripts/runcmd
```

## ArgoCD

List all applications:
```
argocd app list
```

Manually sync applications:
```
argocd app sync kube-01-istio-base kube-02-istio-base
argocd app sync kube-01-istio-cni kube-02-istio-cni
argocd app sync kube-01-istio-pilot kube-02-istio-pilot
argocd app sync kube-01-istio-igws kube-02-istio-igws
argocd app sync kube-01-istio-ewgw kube-02-istio-ewgw
argocd app sync kube-01-httpbin kube-02-httpbin
```

## Calico

Commands to manage Calico:
```
calicoctl get ipPool -o wide --allow-version-mismatch
calicoctl get node -o wide --allow-version-mismatch
```

## Envoy config in VMs

Inspect `config_dump`:
```
multipass exec virt-01 -- curl -s localhost:15000/config_dump | istioctl pc listeners --file -
multipass exec virt-01 -- curl -s localhost:15000/config_dump | istioctl pc routes --file -
multipass exec virt-01 -- curl -s localhost:15000/config_dump | istioctl pc clusters --file -
multipass exec virt-01 -- curl -s localhost:15000/config_dump | istioctl pc secret --file -
```

## Tcpdump

Tcpdump traffic to port `8080`:
```
k --context kube-01 -n httpbin exec -it httpbin-69d46696d6-c6p6m -c istio-proxy -- sudo tcpdump dst port 8080 -A
k --context kube-02 -n httpbin exec -it httpbin-7f859459c6-lkfbr -c istio-proxy -- sudo tcpdump dst port 8080 -A
```

Send requests to the service above:
```
k --context kube-01 -n httpbin exec -it sleep-5f694bf9d6-vqbfv -- curl http://httpbin:5000/get
k --context kube-02 -n httpbin exec -it sleep-74456b78d-8hwd7 -- curl http://httpbin:5000/get
```

Same thing but using the VM:
```
multipass exec virt-01 -- curl httpbin:5000/get
```

## Certificates

Connect to the externally exposed `istiod` service and inspect the certificate bundle it presents:
```
step certificate inspect --bundle --servername istiod-1-14-1.istio-system.svc https://192.168.64.3:15012 --roots ./tmp/istio-ca/root-cert.pem
step certificate inspect --bundle --servername istiod-1-14-1.istio-system.svc https://192.168.64.3:15012 --insecure
```

As a client, inspect the certificate provided by a workload:
```
k -n httpbin exec -it sleep-66b495d847-jkbpg -c istio-proxy -- openssl s_client -showcerts httpbin:5000
```

## Workload endpoints

List all the endpoints for a given cluster/workload:
```
istioctl --context kube-01 pc endpoint deploy/httpbin.httpbin | egrep '^END|httpbin'
istioctl --context kube-02 pc endpoint deploy/httpbin.httpbin | egrep '^END|httpbin'
```

## Devel

Provision only one VM
```
source ./lib/misc.sh && launch_k8s kube-00
source ./lib/misc.sh && launch_vms virt-01
```
