#!/usr/bin/env bash

#------------------------------------------------------------------------------
# Variables
#------------------------------------------------------------------------------

export MNGR="mnger-1"
export DOMAIN="demo.lab"
export PASS='meshlab123'
readonly MNGR DOMAIN PASS
export SECTIONS=()

# Define workload cells and their clusters
declare -A CELLS=(
  [pasta]="pasta-1 pasta-2"
  [pizza]="pizza-1 pizza-2"
)

# Reverse map (cluster -> cell), covers manager + all workload clusters
# shellcheck disable=SC2034 # used by bin/meshlab
declare -A CELL_OF=(
  [${MNGR}]=mngr
  [pasta-1]=pasta [pasta-2]=pasta
  [pizza-1]=pizza [pizza-2]=pizza
)

# Colors
readonly CYAN='\e[1;36m'
readonly DIM='\e[2m'
readonly RST='\e[0m'

#------------------------------------------------------------------------------
# List the first ${WLCNT} workload cells (or their clusters)
#------------------------------------------------------------------------------

# List the first ${WLCNT} workload cells
cells() {
  local count=0
  for cell in "${!CELLS[@]}"; do
    ((++count > ${WLCNT:-1})) && break
    echo -n "${cell} "
  done
}

# Manager cell + workload cells above
all_cells() {
  echo "mngr $(cells)"
}

# List the first ${WLCNT} workload clusters
clusters() {
  local count=0
  for cell in "${!CELLS[@]}"; do
    ((++count > ${WLCNT:-1})) && break
    echo -n "${CELLS[${cell}]} "
  done
}

# Manager cluster + workload clusters above
all_clusters() {
  echo "${MNGR} $(clusters)"
}

#------------------------------------------------------------------------------
# Returns the CIDR for the given cluster
#------------------------------------------------------------------------------

cluster_cidr() {
  yq '.ipam.operator.clusterPoolIPv4PodCIDRList' < ./charts/cilium/values/"${1}".yaml
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
       END { printf "%.0f", rx + tx }' /proc/net/dev
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
  for cluster in $(all_clusters); do
    IP[${cluster}]=$(docker inspect "${cluster}-control-plane" |
      jq -r '.[].NetworkSettings.Networks.kind.IPAddress')
  done; IP_INIT=true
}
