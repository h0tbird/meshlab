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
# Set variables
#------------------------------------------------------------------------------

BASE_IMAGE_TAG ?= 1.28.2
GIT_REVISION ?= release-1.28

NEW_IMAGE_REGISTRY ?= ghcr.io/h0tbird
NEW_IMAGE_TAG ?= 1.28.2-patch.2

#------------------------------------------------------------------------------
# Targets
#------------------------------------------------------------------------------

.PHONY: pilot-agent
pilot-agent: IMG := ${NEW_IMAGE_REGISTRY}/proxyv2:${NEW_IMAGE_TAG}
pilot-agent:
	@echo "Building pilot-agent"
	cd ../istio
	git fetch upstream --tags
	git checkout ${GIT_REVISION}
	docker buildx build --progress=plain -t ${IMG} \
		--platform linux/amd64,linux/arm64 \
		-f ../meshlab/hack/Dockerfile.pilot-agent \
		--build-arg="VERSION=${NEW_IMAGE_TAG}" \
		--build-arg="REGISTRY=${NEW_IMAGE_REGISTRY}" \
		--build-arg="GIT_SHA=$$(git rev-parse HEAD)" \
		--build-arg="BASE_IMAGE_TAG=${BASE_IMAGE_TAG}" \
		--push .

.PHONY: pilot-discovery
pilot-discovery: IMG := ${NEW_IMAGE_REGISTRY}/pilot:${NEW_IMAGE_TAG}
pilot-discovery:
	@echo "Building pilot-discovery"
	cd ../istio
	git fetch upstream --tags
	git checkout ${GIT_REVISION}
	docker buildx build --progress=plain -t ${IMG} \
		--platform linux/amd64,linux/arm64 \
		-f ../meshlab/hack/Dockerfile.pilot-discovery \
		--build-arg="VERSION=${NEW_IMAGE_TAG}" \
		--build-arg="REGISTRY=${NEW_IMAGE_REGISTRY}" \
		--build-arg="GIT_SHA=$$(git rev-parse HEAD)" \
		--build-arg="BASE_IMAGE_TAG=${BASE_IMAGE_TAG}" \
		--push .

.PHONY: toolbox
toolbox: IMG := ${NEW_IMAGE_REGISTRY}/meshlab/toolbox:latest
toolbox:
	@echo "Building toolbox"
	docker buildx build --progress=plain -t ${IMG} \
		--platform linux/amd64,linux/arm64 \
		-f ./hack/Dockerfile.toolbox \
		--push .
