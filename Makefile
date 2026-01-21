#------------------------------------------------------------------------------
# Ensures all lines in a recipe are executed within a single shell instance
# instead of invoking a new shell for each line. Using bash enables execution
# of bash-specific commands. The options enforce exiting if a recipe line
# fails (non-zero exit code) or if any command in a pipeline fails.
#------------------------------------------------------------------------------

.ONESHELL:
BASH_PATH := $(shell which bash)
SHELL = $(BASH_PATH)
.SHELLFLAGS = -o pipefail -ec

#------------------------------------------------------------------------------
# Variables
#------------------------------------------------------------------------------

ISTIO_HUB ?= localhost:5005
ISTIO_TAG ?= latest
ISTIO_TARGETS ?= pilot proxyv2 install-cni istioctl ztunnel ext-authz
ISTIO_SOURCE ?= https://github.com/h0tbird/forked-istio

#------------------------------------------------------------------------------
# Toolbox image used by WorkflowTemplates, e.g. to populate Vault.
#------------------------------------------------------------------------------

.PHONY: toolbox
toolbox: IMG := ${NEW_IMAGE_REGISTRY}/meshlab/toolbox:latest
toolbox:
	@echo "Building toolbox"
	docker buildx build --progress=plain -t ${IMG} \
		--platform linux/amd64,linux/arm64 \
		-f ./hack/Dockerfile.toolbox \
		--push .

#------------------------------------------------------------------------------
# Build Istio images using Istio's own build system.
#   make istio-images ISTIO_HUB=ghcr.io/h0tbird ISTIO_TAG=1.28.3-patch.1-dev
#------------------------------------------------------------------------------

.PHONY: istio-images
istio-images: DOCKER_HOST := unix:///var/run/docker.sock
istio-images:
	@echo "Building Istio images"
	rm ~/.docker/config.json || true \
	&& echo ${GITHUB_TOKEN} | docker login ghcr.io -u ${GITHUB_USER} --password-stdin 2>/dev/null \
	&& cd /workspaces/istio \
	&& make docker.push DOCKER_ARCHITECTURES="linux/amd64,linux/arm64" \
	HUB=${ISTIO_HUB} TAG=${ISTIO_TAG} DOCKER_TARGETS="${ISTIO_TARGETS}"  \
	&& cp ~/.docker/config.json.bkp ~/.docker/config.json

#------------------------------------------------------------------------------
# Add labels to Istio images.
#  make istio-labels ISTIO_HUB=ghcr.io/h0tbird ISTIO_TAG=1.28.3-patch.1-dev
#------------------------------------------------------------------------------

.PHONY: istio-labels
istio-labels:
	@for target in ${ISTIO_TARGETS}; do \
		echo "Adding labels to $${target}"; \
		crane mutate ${ISTIO_HUB}/$${target}:${ISTIO_TAG} \
			--label org.opencontainers.image.source=${ISTIO_SOURCE}; \
	done
