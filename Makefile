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

ISTIO_VERSION ?= 1.24.3
REGISTRY ?= ghcr.io/h0tbird
MESHLAB_PATH ?= ~/git/h0tbird/meshlab
ISTIO_PATH ?= ~/git/h0tbird/forked-istio

#------------------------------------------------------------------------------
# Targets
#------------------------------------------------------------------------------

.PHONY: pilot-agent
pilot-agent: IMG := ${REGISTRY}/proxyv2:${ISTIO_VERSION}
pilot-agent:
	@echo "Building pilot-agent"
	cd ${ISTIO_PATH}
	git fetch upstream tag $(ISTIO_VERSION)
	git checkout $(ISTIO_VERSION)
	docker buildx build -t ${IMG} \
		--platform linux/amd64,linux/arm64 \
		-f ${MESHLAB_PATH}/hack/Dockerfile.pilot-agent \
		--build-arg VERSION=${ISTIO_VERSION} \
		--build-arg REGISTRY=${REGISTRY} \
		--build-arg GIT_SHA=$(git rev-parse HEAD) \
		--push .

.PHONY: pilot-discovery
pilot-discovery: IMG := ${REGISTRY}/pilot:${ISTIO_VERSION}
pilot-discovery:
	@echo "Building pilot-discovery"
	cd ${ISTIO_PATH}
	git fetch upstream tag $(ISTIO_VERSION)
	git checkout $(ISTIO_VERSION)
	docker buildx build -t ${IMG} \
		--platform linux/amd64,linux/arm64 \
		-f ${MESHLAB_PATH}/hack/Dockerfile.pilot-discovery \
		--build-arg VERSION=${ISTIO_VERSION} \
		--build-arg REGISTRY=${REGISTRY} \
		--build-arg GIT_SHA=$(git rev-parse HEAD) \
		--push .
