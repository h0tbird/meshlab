#------------------------------------------------------------------------------
#
#------------------------------------------------------------------------------

# tail -f /Library/Logs/Multipass/multipassd.log
# cat /var/lib/cloud/instance/user-data.txt 
# cat /var/lib/cloud/instance/scripts/runcmd
# cat /var/log/cloud-init-output.log

#------------------------------------------------------------------------------
#
#------------------------------------------------------------------------------

function launch_k8s {
  multipass launch --name $1 --cpus 2 --mem 2G --disk 8G --mount tmp/$1:/mnt/host --cloud-init - <<- EOF
	#cloud-config
	write_files:
	- path: /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl
	  content: CltwbHVnaW5zLm9wdF0KICBwYXRoID0gIi92YXIvbGliL3JhbmNoZXIvazNzL2FnZW50L2NvbnRhaW5lcmQiCgpbcGx1Z2lucy5jcmldCiAgc3RyZWFtX3NlcnZlcl9hZGRyZXNzID0gIjEyNy4wLjAuMSIKICBzdHJlYW1fc2VydmVyX3BvcnQgPSAiMTAwMTAiCiAgZW5hYmxlX3NlbGludXggPSBmYWxzZQogIHNhbmRib3hfaW1hZ2UgPSAicmFuY2hlci9taXJyb3JlZC1wYXVzZTozLjYiCgpbcGx1Z2lucy5jcmkuY29udGFpbmVyZF0KICBzbmFwc2hvdHRlciA9ICJvdmVybGF5ZnMiCiAgZGlzYWJsZV9zbmFwc2hvdF9hbm5vdGF0aW9ucyA9IHRydWUKCltwbHVnaW5zLmNyaS5jb250YWluZXJkLnJ1bnRpbWVzLnJ1bmNdCiAgcnVudGltZV90eXBlID0gImlvLmNvbnRhaW5lcmQucnVuYy52MiIKCltwbHVnaW5zLmNyaS5jb250YWluZXJkLnJ1bnRpbWVzLnJ1bmMub3B0aW9uc10KCVN5c3RlbWRDZ3JvdXAgPSBmYWxzZQoKW3BsdWdpbnMuY3JpLnJlZ2lzdHJ5Lm1pcnJvcnNdCiAgW3BsdWdpbnMuY3JpLnJlZ2lzdHJ5Lm1pcnJvcnMuImRvY2tlci5pbyJdCiAgICBlbmRwb2ludCA9IFsiaHR0cDovLzE5Mi4xNjguNjQuMTo1MDAxIl0K
	  encoding: b64
	- path: /etc/calico-installation.yaml
	  content: LS0tCmFwaVZlcnNpb246IG9wZXJhdG9yLnRpZ2VyYS5pby92MQpraW5kOiBJbnN0YWxsYXRpb24KbWV0YWRhdGE6CiAgbmFtZTogZGVmYXVsdApzcGVjOgogIGNhbGljb05ldHdvcms6CiAgICBjb250YWluZXJJUEZvcndhcmRpbmc6IEVuYWJsZWQKICAgIGlwUG9vbHM6CiAgICAtIGJsb2NrU2l6ZTogMjYKICAgICAgY2lkcjogMTAuNDIuMC4wLzE2CiAgICAgIGVuY2Fwc3VsYXRpb246IFZYTEFOQ3Jvc3NTdWJuZXQKICAgICAgbmF0T3V0Z29pbmc6IEVuYWJsZWQKICAgICAgbm9kZVNlbGVjdG9yOiBhbGwoKQotLS0KYXBpVmVyc2lvbjogb3BlcmF0b3IudGlnZXJhLmlvL3YxCmtpbmQ6IEFQSVNlcnZlciAKbWV0YWRhdGE6IAogIG5hbWU6IGRlZmF1bHQgCnNwZWM6IHt9Cg==
	  encoding: b64
	runcmd:
	- 'curl -sfL https://get.k3s.io |
	  INSTALL_K3S_EXEC="--flannel-backend=none --cluster-cidr=10.42.0.0/16 --disable-network-policy --disable=traefik" \
	  CONTAINERD_LOG_LEVEL="debug" \
	  K3S_KUBECONFIG_MODE="644" sh -s -'
	- kubectl create -f https://projectcalico.docs.tigera.io/manifests/tigera-operator.yaml
	- kubectl create -f /etc/calico-installation.yaml
	- sleep 10; kubectl wait --for=condition=Ready nodes --all --timeout=60s
	- kubectl label --overwrite node $1 topology.kubernetes.io/region=$1
	- IP=\$(hostname -I | awk '{print \$1}')
	- 'kubectl config view --raw | sed "s/127\.0\.0\.1/\${IP}/g; s/: default/: $1/g" \
	  > /home/ubuntu/config'
	EOF
  multipass exec $1 -- cp config /mnt/host
}
