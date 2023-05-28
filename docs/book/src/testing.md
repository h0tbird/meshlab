# Testing

The tests in this section should validate all functionalities.

Send requests to the `blau` services from an authenticated in-cluster pod:
```console
k --context pasta-1 -n applab-blau exec -i deployment/sleep -- curl -s httpbin/hostname | jq -r '.hostname'
k --context pasta-1 -n applab-blau exec -i deployment/sleep -- bash -c "echo hello | nc -N echo 70"
```

Send requests to the `blau` services from an unauthenticated out-of-cluster workstation:
```console
curl -skm2 --resolve httpbin.blau.demo.lab:443:192.168.64.3 https://httpbin.blau.demo.lab/hostname | jq -r '.hostname'
echo hello | gnutls-cli 192.168.64.3 -p 70 --sni-hostname echo.blau.demo.lab --insecure --logfile=/tmp/echo.log
```

Same as above but with certificate validation:
```console
k --context pasta-1 -n istio-system get secret cacerts -o json | jq -r '.data."ca.crt"' | base64 -d > /tmp/ca.crt
curl -sm2 --cacert /tmp/ca.crt --resolve httpbin.blau.demo.lab:443:192.168.64.3 https://httpbin.blau.demo.lab/hostname | jq -r '.hostname'
echo hello | openssl s_client -servername echo.blau.demo.lab -connect 192.168.64.3:70 -quiet -CAfile /tmp/ca.crt
```

Send requests to the `blau` service from an authenticated out-of-cluster VM:
```console
for i in {1..20}; do multipass exec virt-01 -- curl -s httpbin/hostname | jq -r '.hostname'; done | sort | uniq -c | sort -rn
```
