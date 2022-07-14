#------------------------------------------------------------------------------
# Base64 encode config files
#------------------------------------------------------------------------------

CONTAINERD_CONFIG=$(base64 -w0 conf/containerd.tmpl)
CALICO_CONFIG=$(base64 -w0 conf/calico.yaml)

#------------------------------------------------------------------------------
#
#------------------------------------------------------------------------------

# tail -f /Library/Logs/Multipass/multipassd.log
# cat /var/lib/cloud/instance/user-data.txt 
# cat /var/lib/cloud/instance/scripts/runcmd
# cat /var/log/cloud-init-output.log

function launch_k8s {

  # Setup the VM with cloud-config
  multipass launch --name $1 --cpus 2 --mem 2G --disk 8G --mount tmp/$1:/mnt/host --cloud-init - <<- EOF
	#cloud-config
	write_files:
	- path: /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl
	  content: ${CONTAINERD_CONFIG}
	  encoding: b64
	- path: /etc/calico-installation.yaml
	  content: ${CALICO_CONFIG}
	  encoding: b64
	runcmd:
	- |
	  curl -sfL https://get.k3s.io |
	  INSTALL_K3S_EXEC="--flannel-backend=none --cluster-cidr=10.42.0.0/16 --disable-network-policy --disable=traefik" \
	  CONTAINERD_LOG_LEVEL="debug" \
	  K3S_KUBECONFIG_MODE="644" sh -s -
	  kubectl create -f https://projectcalico.docs.tigera.io/manifests/tigera-operator.yaml
	  kubectl create -f /etc/calico-installation.yaml
	  sleep 10; kubectl wait --for=condition=Ready nodes --all --timeout=60s
	  kubectl label --overwrite node $1 topology.kubernetes.io/region=$1
	  IP=\$(hostname -I | awk '{print \$1}')
	  kubectl config view --raw | sed "s/127\.0\.0\.1/\${IP}/g; s/: default/: $1/g" > /home/ubuntu/config
	  [ "\$(hostname)" = "kube-00" ] && {
	     kubectl create ns argocd
	     kubectl -n argocd apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	     kubectl -n argocd patch svc argocd-server -p '{"spec": {"type": "LoadBalancer"}}'
	  }
	EOF

  # Share the k8s config with the host
  multipass exec $1 -- cp config /mnt/host
}
