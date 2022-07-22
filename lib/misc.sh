#------------------------------------------------------------------------------
#
#------------------------------------------------------------------------------

# tail -f /Library/Logs/Multipass/multipassd.log
# cat /var/lib/cloud/instance/user-data.txt 
# cat /var/lib/cloud/instance/scripts/runcmd
# cat /var/log/cloud-init-output.log

function launch_vms {
  multipass launch --name $1 --cpus 1 --mem 1G --disk 8G --mount tmp/$1:/mnt/host
}

function launch_k8s {

  # Base64 encoded config files
  CONTAINERD_CONFIG=$(base64 -w0 conf/containerd.tmpl)
  CALICO_CONFIG=$(base64 -w0 conf/calico.yaml)
  ROOTCA_CERT=$(base64 -w0 ./tmp/istio-ca/root-cert.pem)
  ROOTCA_KEY=$(base64 -w0 ./tmp/istio-ca/root-key.pem)

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
	- path: /etc/certs/root-cert.pem
	  content: ${ROOTCA_CERT}
	  permissions: '0600'
	  encoding: b64
	- path: /etc/certs/root-key.pem
	  content: ${ROOTCA_KEY}
	  permissions: '0600'
	  encoding: b64
	 
	runcmd:
	- |
	  
	  set -xo errexit
	  
	  #-------------
	  # Install k3s
	  #-------------
	  
	  curl -sfL https://get.k3s.io |
	  INSTALL_K3S_EXEC="--flannel-backend=none --cluster-cidr=10.42.0.0/16 --disable-network-policy --disable=traefik" \
	  CONTAINERD_LOG_LEVEL="debug" \
	  K3S_KUBECONFIG_MODE="644" sh -s -
	  
	  #----------------
	  # Install Calico
	  #----------------
	  
	  kubectl create -f https://projectcalico.docs.tigera.io/manifests/tigera-operator.yaml
	  kubectl create -f /etc/calico-installation.yaml
	  sleep 10; kubectl wait --for=condition=Ready nodes --all --timeout=60s
	  kubectl label --overwrite node $1 topology.kubernetes.io/region=$1
	  
	  #------------
	  # Kubeconfig
	  #------------
	  
	  IP=\$(hostname -I | awk '{print \$1}')
	  kubectl config view --raw | sed "s/127\.0\.0\.1/\${IP}/g; s/: default/: $1/g" > /home/ubuntu/config
	  
	  #--------------------
	  # Generate Istio ICA
	  #--------------------
	  
	  # Install step CLI
	  wget -qO- https://github.com/smallstep/cli/releases/download/v0.21.0/step_linux_0.21.0_$(arch).tar.gz |
	  tar zxv --strip-components=2 -C /usr/bin/ step_0.21.0/bin/step
	  
	  [ "\$(hostname)" != "kube-00" ] && {
	  
	    # Generate ICA
	    step certificate create \
	    "Istio intermediate CA" \
	    /etc/certs/ca-cert.pem \
	    /etc/certs/ca-key.pem \
	    --ca /etc/certs/root-cert.pem \
	    --ca-key /etc/certs/root-key.pem \
	    --profile intermediate-ca \
	    --san *.example.com \
	    --not-after 43800h \
	    --no-password \
	    --insecure \
	    --kty RSA
	  
	    # Generate bundle
	    step certificate bundle \
	    /etc/certs/ca-cert.pem \
	    /etc/certs/root-cert.pem \
	    /etc/certs/cert-chain.pem
	  
	    # Create a cacerts secret
	    kubectl create namespace istio-system
	    kubectl -n istio-system create secret generic cacerts \
	    --from-file=/etc/certs/ca-cert.pem \
	    --from-file=/etc/certs/ca-key.pem \
	    --from-file=/etc/certs/root-cert.pem \
	    --from-file=/etc/certs/cert-chain.pem
	  }
	  
	  #----------------
	  # Install ArgoCD
	  #----------------
	  
	  [ "\$(hostname)" = "kube-00" ] && {
	     kubectl create ns argocd
	     kubectl -n argocd apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	     kubectl -n argocd patch svc argocd-server -p '{"spec": {"type": "LoadBalancer"}}'
	  } || true
	EOF

  # Share the k8s config with the host
  multipass exec $1 -- cp config /mnt/host
}
