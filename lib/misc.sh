#!/bin/bash

# shellcheck source=/dev/null
source lib/common.sh

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
# Used to provision k8s clusters
#------------------------------------------------------------------------------

function launch_k8s {

  NAME="$1"
  CELL="$2"
  VERSION="$3"

  # Base64 encoded config files
  REG_CONFIG=$(base64 -w0 conf/registries.yaml)
  K3S_CONFIG=$(base64 -w0 conf/k3s.yaml)

  # Setup the VM with cloud-config
  multipass launch --name "${NAME}" --cpus 2 --memory 5G --disk 12G --cloud-init - <<- EOF
	#cloud-config

	write_files:
	- path: /etc/rancher/k3s/registries.yaml
	  content: ${REG_CONFIG}
	  encoding: b64
	- path: /etc/rancher/k3s/config.yaml
	  content: ${K3S_CONFIG}
	  encoding: b64

	runcmd:
	- |

	  set -xo errexit

	  #------------------
	  # Setup registries
	  #------------------

	  IP=\$(ip r | awk '/default/ {print \$3}')
	  sed -i "s/XXX/\${IP}/g" /etc/rancher/k3s/registries.yaml

	  #-------------
	  # Install k3s
	  #-------------

	  while ! curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${VERSION} \
	  INSTALL_K3S_EXEC="--cluster-domain ${CELL}.local --cluster-cidr $(clusterCIDR "${NAME}")" \
	  sh -s -; do sleep 1; done; while ! kubectl get nodes | grep -q master; do sleep 1; done

	  #----------------
	  # Topology setup
	  #----------------

	  kubectl label --overwrite node ${NAME} topology.kubernetes.io/region=milky-way
	  kubectl label --overwrite node ${NAME} topology.kubernetes.io/zone=solar-system
	  kubectl label --overwrite node ${NAME} topology.istio.io/subzone=${NAME}

	  #------------
	  # Kubeconfig
	  #------------

	  IP=\$(hostname -I | awk '{print \$1}')
	  kubectl config view --raw | sed "s/127\.0\.0\.1/\${IP}/g; s/: default/: ${NAME}/g" > /home/ubuntu/config
	EOF

	# Copy the kubeconfig to the host
	multipass transfer --parents "${NAME}:/home/ubuntu/config" "./tmp/${NAME}/config"
}
