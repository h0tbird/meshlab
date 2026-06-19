#!/usr/bin/env bash

#------------------------------------------------------------------------------
# Variables
#------------------------------------------------------------------------------

export MNGR="mnger-1"
export DOMAIN="demo.lab"
export PASS='meshlab123'
export ZOT_HOST="zot"
export ZOT_PORT=8080
export ZOT_LOCAL_PORT=8086
export ZOT_LOCAL="127.0.0.1:${ZOT_LOCAL_PORT}"
export HOST_TMP="${LOCAL_WORKSPACE_FOLDER}/.tmp"
readonly MNGR DOMAIN PASS ZOT_HOST ZOT_PORT ZOT_LOCAL_PORT ZOT_LOCAL HOST_TMP
export SECTIONS=()

# Define workload cells and their clusters
declare -A CELLS=(
  [pasta]="pasta-1 pasta-2"
  [pizza]="pizza-1 pizza-2"
)

# Ordered list of workload cells (associative arrays don't preserve key order)
declare -a CELL_ORDER=( pasta pizza )

# Reverse map (cluster -> cell), covers manager + all workload clusters
# shellcheck disable=SC2034 # used by bin/meshlab
declare -A CELL_OF=(
  [${MNGR}]=mngr
  [pasta-1]=pasta [pasta-2]=pasta
  [pizza-1]=pizza [pizza-2]=pizza
)

# Per-cluster pod CIDRs; unique ranges keep the flat L3 network non-overlapping
# shellcheck disable=SC2034 # used by bin/meshlab
declare -A POD_CIDR=(
  [${MNGR}]="10.41.0.0/16"
  [pasta-1]="10.51.0.0/16" [pasta-2]="10.52.0.0/16"
  [pizza-1]="10.61.0.0/16" [pizza-2]="10.62.0.0/16"
)

# Per-cluster service CIDRs; unique ranges keep the flat L3 network non-overlapping
# shellcheck disable=SC2034 # used by bin/meshlab
declare -A SVC_CIDR=(
  [${MNGR}]="10.141.0.0/16"
  [pasta-1]="10.151.0.0/16" [pasta-2]="10.152.0.0/16"
  [pizza-1]="10.161.0.0/16" [pizza-2]="10.162.0.0/16"
)

# Map of known registries to their API endpoints
# shellcheck disable=SC2034 # used by bin/meshlab
declare -A REGISTRIES=(
  [docker.io]="https://registry-1.docker.io"
  [quay.io]="https://quay.io"
  [ghcr.io]="https://ghcr.io"
  [registry.k8s.io]="https://registry.k8s.io"
  [registry.istio.io]="https://registry.istio.io"
  [ecr-public.aws.com]="https://public.ecr.aws"
)

# Section dependency graph: maps each section to its prerequisites.
# generate_dag_mk() turns this into .tmp/dag.mk, which `meshlab create` runs
# with `make -j` to execute independent sections in parallel.
declare -A DEPS=(
  [cloud-provider-kind]=""
  [pull-through-cache]="cloud-provider-kind"
  [create-clusters]="cloud-provider-kind"
  [add-registries-to-containerd]="create-clusters pull-through-cache"
  [setup-kubeconfig]="create-clusters"
  [setup-flat-network]="create-clusters"
  [install-k8s-gateway]="setup-kubeconfig"
  [setup-coredns]="install-k8s-gateway setup-kubeconfig"
  [setup-argocd]="setup-kubeconfig"
  [register-argocd-clusters]="setup-argocd setup-kubeconfig"
  [install-applicationsets]="register-argocd-clusters"
  [setup-argowf]="setup-kubeconfig"
  [bootstrap-dag]="install-applicationsets setup-argowf"
  [istio-endpoint-discovery]="bootstrap-dag"
  [grafana-git-sync]="bootstrap-dag"
  [kiali-multicluster]="bootstrap-dag"
  [tilt-up]="bootstrap-dag"
  [deploy-workloads]="bootstrap-dag"
  [publish-ports]="bootstrap-dag"
)

# Colors
readonly CYAN='\e[1;36m'
readonly DIM='\e[2m'
readonly RST='\e[0m'

#------------------------------------------------------------------------------
# List the first ${CELL_COUNT} workload cells (or their clusters)
#------------------------------------------------------------------------------

# List the first ${CELL_COUNT} workload cells
cells() {
  local count=0 cell
  for cell in "${CELL_ORDER[@]}"; do
    ((++count > ${CELL_COUNT:-1})) && break
    echo -n "${cell} "
  done
}

# Manager cell + workload cells above
all_cells() {
  echo "mngr $(cells)"
}

# List the first ${CELL_COUNT} workload clusters
clusters() {
  local cell
  for cell in $(cells); do
    echo -n "${CELLS[${cell}]} "
  done
}

# Manager cluster + workload clusters above
all_clusters() {
  echo "${MNGR} $(clusters)"
}

#------------------------------------------------------------------------------
# Prints the given string in turquoise
#------------------------------------------------------------------------------

blue() {
  printf '\n%b%s%b\n\n' "${CYAN}" "$1" "${RST}"
}

#------------------------------------------------------------------------------
# Prints the given string in grey (dim)
#------------------------------------------------------------------------------

grey() {
  printf '%b%s%b\n' "${DIM}" "$1" "${RST}"
}

#------------------------------------------------------------------------------
# Retrieves the external IP of the given service
#------------------------------------------------------------------------------

get_ext_ip() {
  local ip='null'
  until [[ -n "${ip}" && "${ip}" != 'null' ]]; do
    ip=$(kubectl --context="kind-${1}" -n "${2}" get svc "${3}" -o yaml 2>/dev/null | \
      yq '.status.loadBalancer.ingress[0].ip')
    [[ -n "${ip}" && "${ip}" != 'null' ]] || sleep 1
  done
  echo "${ip}"
}

#------------------------------------------------------------------------------
# Publishes the given service in the given VM port
#------------------------------------------------------------------------------

publish() {

  # Get the external IP of the service
  local ip
  ip=$(get_ext_ip "${1}" "${2}" "${3}")

  # Setup socat for additional edge cases
  nohup socat TCP-LISTEN:"${4}",fork TCP:"${ip}":80 &> /dev/null & disown
}

#------------------------------------------------------------------------------
# Wait for all background jobs, fail if any failed
#------------------------------------------------------------------------------

join() {
  local pid status=0
  for pid in $(jobs -p); do wait "${pid}" || status=$?; done
  return "${status}"
}

#------------------------------------------------------------------------------
# Sum of RX+TX bytes across all non-loopback interfaces in this devcontainer
#------------------------------------------------------------------------------

net_bytes() {
  awk '/:/ && $1 !~ /^lo:/ { gsub(":", "", $1); rx += $2; tx += $10 }
       END { printf "%.0f", rx + tx }' /proc/net/dev 2>/dev/null || echo 0
}

#------------------------------------------------------------------------------
# Format a byte count in human-readable IEC units (e.g. 1.2MiB)
#------------------------------------------------------------------------------

human_bytes() {
  numfmt --to=iec-i --suffix=B --format='%.1f' "${1:-0}"
}

#------------------------------------------------------------------------------
# Format a duration in seconds as "<m>m <s>s" (e.g. 5m 12s)
#------------------------------------------------------------------------------

human_time() {
  printf '%dm %ds' $(( ${1:-0} / 60 )) $(( ${1:-0} % 60 ))
}

#------------------------------------------------------------------------------
# Run a command and print its elapsed time and network traffic
#------------------------------------------------------------------------------

measure() {
  local t=${SECONDS}
  local n; n=$(net_bytes)
  "$@"
  local dt=$((SECONDS - t))
  local dn=$(( $(net_bytes) - n ))
  grey "  └── done in ${dt}s ($(human_bytes "${dn}"))"
}

#------------------------------------------------------------------------------
# Retry til success or max attempts reached
#------------------------------------------------------------------------------

retry() {
  local max=3 attempt=1
  until "$@"; do
    if (( attempt >= max )); then
      grey "  └── retry: giving up after ${max} attempts: $*"
      return 1
    fi
    ((attempt++))
    grey "  └── retry ${attempt}/${max} in 2s: $*"
    sleep 2
  done
}

#------------------------------------------------------------------------------
# Manager kubectl and helm helpers
#------------------------------------------------------------------------------

# Helper function k0
k0() {
  kubectl --context "kind-${MNGR}" "${@}"
}

# Helper function h0
h0() {
  retry helm --kube-context "kind-${MNGR}" "${@}"
}

#------------------------------------------------------------------------------
# Cluster IPs (lazy initialization)
#------------------------------------------------------------------------------

declare -gxA IP; IP_INIT=false

ensure_ips() {
  [[ "${IP_INIT}" == true ]] && return 0
  local cluster
  for cluster in $(all_clusters); do
    IP[${cluster}]=$(docker inspect "${cluster}-control-plane" |
      jq -r '.[].NetworkSettings.Networks.kind.IPAddress')
  done; IP_INIT=true
}

#------------------------------------------------------------------------------
# Generate the section DAG as a Makefile fragment
#------------------------------------------------------------------------------

# Emit a Makefile (arg 1) describing every registered section as a phony target
# whose prerequisites come from the DEPS map. Each recipe re-invokes this script
# with `__run-section <name>`, and on failure appends the section name to
# .tmp/failed so the caller can report every failure after a keep-going run.
generate_dag_mk() {
  local out="$1" meshlab section
  meshlab="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/meshlab"
  {
    echo "# Auto-generated by bin/meshlab — do not edit."
    echo "MESHLAB := ${meshlab}"
    echo ".PHONY: all ${SECTIONS[*]}"
    echo
    echo "all: ${SECTIONS[*]}"
    echo
    for section in "${SECTIONS[@]}"; do
      printf '%s:%s\n' "${section}" "${DEPS[${section}]:+ ${DEPS[${section}]}}"
      # $(MESHLAB) is a make variable reference, kept literal on purpose.
      # shellcheck disable=SC2016
      printf '\t@"$(MESHLAB)" __run-section %s || { echo %s >> .tmp/failed; false; }\n\n' \
        "${section}" "${section}"
    done
  } > "${out}"
}

