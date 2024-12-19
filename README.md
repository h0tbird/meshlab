## Generate DNS records
```console
$ docker inspect $(docker ps -f "name=kindccm-" -q) | jq -r '.[] |
select(.Config.Labels."io.x-k8s.cloud-provider-kind.cluster" == "kube-00") |
"\(.NetworkSettings.Networks.kind.IPAddress) \(.Config.Labels."io.x-k8s.cloud-provider-kind.loadbalancer.name" |
split("/")[-1]).mesh.lab"' | sort
172.18.0.11 argocd-server.mesh.lab
172.18.0.12 argo-workflows-server.mesh.lab
172.18.0.13 prometheus-server.mesh.lab
172.18.0.14 vault.mesh.lab
172.18.0.15 grafana.mesh.lab
```
