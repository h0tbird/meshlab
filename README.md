## Generate DNS records
```console
$ docker inspect $(docker ps -f "name=kindccm-" -q) | jq -r '.[] |
  select(.Config.Labels."io.x-k8s.cloud-provider-kind.cluster" == "kube-00") |
  (
    .NetworkSettings.Ports
    | map_values(.[] | .HostPort)
    | to_entries
    | map("http://127.0.0.1:" + .value)
    | .[:2]
    | join(" | ")
  ) as $ports |
  .NetworkSettings.Networks.kind.IPAddress as $ip |
  .Config.Labels."io.x-k8s.cloud-provider-kind.loadbalancer.name" as $lb_name |
  "\($ports) | \($ip) | \($lb_name | split("/")[-1]).demo.lab"
'

http://127.0.0.1:56840 | http://127.0.0.1:56839 | 172.18.0.18 | grafana.demo.lab
http://127.0.0.1:56813 | http://127.0.0.1:56814 | 172.18.0.17 | prometheus-server.demo.lab
http://127.0.0.1:56812 | http://127.0.0.1:56810 | 172.18.0.16 | vault.demo.lab
http://127.0.0.1:56775 | http://127.0.0.1:56776 | 172.18.0.15 | argo-workflows-server.demo.lab
http://127.0.0.1:56686 | http://127.0.0.1:56687 | 172.18.0.14 | argocd-server.demo.lab
http://127.0.0.1:56679 | http://127.0.0.1:56608 | 172.18.0.12 | exdns-k8s-gateway.demo.lab
```
