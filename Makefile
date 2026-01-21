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
#------------------------------------------------------------------------------

.PHONY: istio-images
istio-images: HUB ?= localhost:5005
istio-images: TAG ?= latest
istio-images: DOCKER_TARGETS ?= pilot proxyv2 install-cni istioctl ztunnel ext-authz
istio-images:
	@echo "Building Istio images"
	rm ~/.docker/config.json || true \
	&& echo ${GITHUB_TOKEN} | docker login ghcr.io -u ${GITHUB_USER} --password-stdin 2>/dev/null \
	&& cd /workspaces/istio \
	&& DOCKER_ARCHITECTURES="linux/amd64,linux/arm64" \
	&& DOCKER_BUILD_ARGS="--label org.opencontainers.image.source=https://github.com/h0tbird/forked-istio" \
	DOCKER_HOST= HUB=${HUB} TAG=${TAG} make docker.push \
	&& cp ~/.docker/config.json.bkp ~/.docker/config.json
