#!/bin/bash

#------------------------------------------------------------------------------
# Used to provision virt-01
#------------------------------------------------------------------------------

function launch_vms {

  # Base64 encoded config files
  HTTPBIN_SYSTEMD=$(base64 -w0 conf/httpbin.service)

  # Setup the VM with cloud-config
  multipass launch --name "$1" --cpus 1 --memory 1G --disk 8G --mount "tmp/$1:/mnt/host" --cloud-init - <<- EOF
	#cloud-config
	
	write_files:
	- path: /etc/systemd/system/httpbin.service
	  content: ${HTTPBIN_SYSTEMD}
	  encoding: b64
	
	packages:
	- golang-go
	- net-tools
	
	runcmd:
	- |
	  
	  set -xo errexit
	  
	  #--------------
	  # Install step
	  #--------------
	  
	  wget -qO- https://github.com/smallstep/cli/releases/download/v0.23.2/step_linux_0.23.2_$(arch).tar.gz |
	  tar zxv --strip-components=2 -C /usr/bin/ step_0.23.2/bin/step
	  
	  #-----------------
	  # Install httpbin
	  #-----------------
	  
	  git clone https://github.com/chinaran/go-httpbin.git; cd go-httpbin
	  GOCACHE=/root/.cache/go-build GOPATH=/root/go CGO_ENABLED=0 \
	  go build -ldflags="-s -w" -o /usr/local/bin/go-httpbin ./cmd/go-httpbin
	  systemctl start httpbin
	EOF
}

#------------------------------------------------------------------------------
# Used to provision kube-00, kube-01 and kube-02
#------------------------------------------------------------------------------

function launch_k8s {

  # Base64 encoded config files
  REG_CONFIG=$(base64 -w0 conf/registries.yaml)
  K3S_CONFIG=$(base64 -w0 conf/k3s.yaml)
  # ROOTCA_CERT=$(base64 -w0 ./tmp/istio-ca/root-cert.pem)
  # ROOTCA_KEY=$(base64 -w0 ./tmp/istio-ca/root-key.pem)

  # Setup the VM with cloud-config
  multipass launch --name "$1" --cpus 2 --memory 5G --disk 10G --mount "tmp/$1:/mnt/host" --cloud-init - <<- EOF
	#cloud-config
	 
	write_files:
	- path: /etc/rancher/k3s/registries.yaml
	  content: ${REG_CONFIG}
	  encoding: b64
	- path: /etc/rancher/k3s/config.yaml
	  content: ${K3S_CONFIG}
	  encoding: b64
	# - path: /etc/certs/root-cert.pem
	#   content: ${ROOTCA_CERT}
	#   permissions: '0600'
	#   encoding: b64
	# - path: /etc/certs/root-key.pem
	#   content: ${ROOTCA_KEY}
	#   permissions: '0600'
	#   encoding: b64
	 
	runcmd:
	- |
	  
	  set -xo errexit
	  
	  #-------------
	  # Install k3s
	  #-------------
	  
	  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik" sh -s -
	  sleep 5; kubectl wait --for=condition=Ready nodes --all --timeout=60s
	  
	  #----------------
	  # Topology setup
	  #----------------
	  
	  kubectl label --overwrite node $1 topology.kubernetes.io/region=milky-way
	  kubectl label --overwrite node $1 topology.kubernetes.io/zone=solar-system
	  kubectl label --overwrite node $1 topology.istio.io/subzone=$1
	  
	  #------------
	  # Kubeconfig
	  #------------
	  
	  IP=\$(hostname -I | awk '{print \$1}')
	  kubectl config view --raw | sed "s/127\.0\.0\.1/\${IP}/g; s/: default/: $1/g" > /home/ubuntu/config
	  
	  # #--------------------
	  # # Generate Istio ICA
	  # #--------------------
	  # 
	  # # Install step CLI
	  # wget -qO- https://github.com/smallstep/cli/releases/download/v0.21.0/step_linux_0.21.0_$(arch).tar.gz |
	  # tar zxv --strip-components=2 -C /usr/bin/ step_0.21.0/bin/step
	  # 
	  # [ "\$(hostname)" != "kube-00" ] && {
	  # 
	  #   # Generate ICA
	  #   step certificate create \
	  #   "Istio intermediate CA" \
	  #   /etc/certs/ca-cert.pem \
	  #   /etc/certs/ca-key.pem \
	  #   --ca /etc/certs/root-cert.pem \
	  #   --ca-key /etc/certs/root-key.pem \
	  #   --profile intermediate-ca \
	  #   --san *.example.com \
	  #   --not-after 43800h \
	  #   --no-password \
	  #   --insecure \
	  #   --kty RSA
	  # 
	  #   # Generate bundle
	  #   step certificate bundle \
	  #   /etc/certs/ca-cert.pem \
	  #   /etc/certs/root-cert.pem \
	  #   /etc/certs/cert-chain.pem
	  # 
	  #   # Create a cacerts secret
	  #   kubectl create namespace istio-system
	  #   kubectl -n istio-system create secret generic cacerts \
	  #   --from-file=/etc/certs/ca-cert.pem \
	  #   --from-file=/etc/certs/ca-key.pem \
	  #   --from-file=/etc/certs/root-cert.pem \
	  #   --from-file=/etc/certs/cert-chain.pem
	  # }
	  
	  #----------------
	  # Install ArgoCD
	  #----------------
	  
	  [ "\$(hostname)" = "kube-00" ] && {
	     kubectl create ns argocd
	     kubectl -n argocd apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	     kubectl -n argocd patch svc argocd-server -p '{"spec": {"type": "LoadBalancer"}}'
	  } || true

	  #-------------------------------
	  # Wait for all pods to be ready
	  #-------------------------------
	  
	  sleep 5; kubectl wait --for=condition=Ready --timeout=300s pods --all -A
	EOF

  # Share the k8s config with the host
  multipass exec "$1" -- cp config /mnt/host
}
