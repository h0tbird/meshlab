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
#  make toolbox REGISTRY=ghcr.io/h0tbird
#------------------------------------------------------------------------------

.PHONY: toolbox
toolbox: IMG := ${REGISTRY}/meshlab/toolbox:latest
toolbox:
	@echo "Building toolbox"
	docker buildx build --progress=plain -t ${IMG} \
		--platform linux/amd64,linux/arm64 \
		-f ./hack/Dockerfile.toolbox \
		--push .

#------------------------------------------------------------------------------
# Build Istio binaries using Istio's own build system.
#------------------------------------------------------------------------------

.PHONY: istio-binaries
istio-binaries: DOCKER_HOST := unix:///var/run/docker.sock
istio-binaries:
	@echo "Building Istio binaries"
	cd /workspaces/istio \
	&& make build-linux

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
# Build Istio charts using Istio's own build system.
#  make istio-charts HUB=ghcr.io/h0tbird VERSION=1.28.3-patch.1-dev
#------------------------------------------------------------------------------

.PHONY: istio-charts
istio-charts: CHARTS := base gateway istio-cni istio-control/istio-discovery ztunnel
istio-charts:
	@echo "Building Istio charts"
	cd /workspaces/istio \
	&& for CHART in ${CHARTS}; do \
		yq -i '._internal_defaults_do_not_set.global.hub = "${HUB}"' manifests/charts/$${CHART}/values.yaml; \
		yq -i '._internal_defaults_do_not_set.global.tag = "${VERSION}"' manifests/charts/$${CHART}/values.yaml; \
		yq -i '._internal_defaults_do_not_set.global.variant = ""' manifests/charts/$${CHART}/values.yaml; \
		helm package manifests/charts/$${CHART} --app-version ${VERSION} --version ${VERSION} --destination /tmp/charts; \
	done \
	&& git restore manifests/charts \
	&& git checkout helm-repo \
	&& mv /tmp/charts/*.tgz . \
	&& helm repo index . --url https://h0tbird.github.io/forked-istio \
	&& git add . \
	&& git commit -m "Istio charts for ${VERSION}" \
	&& git push

#------------------------------------------------------------------------------
# Add labels to Istio images.
#  make istio-labels ISTIO_HUB=ghcr.io/h0tbird ISTIO_TAG=1.28.3-patch.1-dev
#
# GitHub Container Registry: Repository Connection
#
# The org.opencontainers.image.source label only triggers repository linking
# when present during the initial push. Relabeling images afterward (e.g., with
# crane) does not create the connection. There is no REST API, GraphQL mutation,
# or gh CLI command to link a repository to an existing package programmatically.
#
# Workaround: Manually connect via GitHub UI (Package → Connect repository).
# This is a one-time setup per package.
#------------------------------------------------------------------------------

.PHONY: istio-labels
istio-labels:
	@for target in ${ISTIO_TARGETS}; do \
		echo "Adding labels to $${target}"; \
		crane mutate ${ISTIO_HUB}/$${target}:${ISTIO_TAG} \
			--label org.opencontainers.image.source=${ISTIO_SOURCE}; \
	done
