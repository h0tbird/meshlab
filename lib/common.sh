#!/usr/bin/env bash

#------------------------------------------------------------------------------
# Variables
#------------------------------------------------------------------------------

export MNGR="mnger-1"
export DOMAIN="demo.lab"
export PASS='meshlab123'

# Define workload cells and their clusters (mngr is tracked separately via ${MNGR})
declare -A CELLS=(
  [pasta]="pasta-1 pasta-2"
  [pizza]="pizza-1 pizza-2"
)

# Runnable sections (in order)
export SECTIONS=()

# Colors
CYAN='\e[1;36m'
DIM='\e[2m'
RST='\e[0m'

#------------------------------------------------------------------------------
# List cells and clusters
#------------------------------------------------------------------------------

function list {

  local count=0
  local limit="${3:-0}"

  for CELL in "${!CELLS[@]}"; do

    [[ "${2}" == "wkld" && "${CELL}" == "mngr" ]] && continue
    [[ "${CELL}" != "mngr" ]] && ((count++))
    [[ "${limit}" -gt 0 && "${count}" -gt "${limit}" ]] && break

    case $1 in
      "cells")
        echo -n "${CELL} " ;;
      "clusters")
        echo -n "${CELLS[${CELL}]} " ;;
    esac
  done
}

#------------------------------------------------------------------------------
# Returns the CIDR for the given cluster
#------------------------------------------------------------------------------

function clusterCIDR {
  yq '.ipam.operator.clusterPoolIPv4PodCIDRList' < ./charts/cilium/values/"${1}".yaml
}

#------------------------------------------------------------------------------
# Prints the given string in turquoise
#------------------------------------------------------------------------------

function blue {
  echo -e "\n${CYAN}$1${RST}\n"
}

#------------------------------------------------------------------------------
# Prints the given string in grey (dim)
#------------------------------------------------------------------------------

function grey {
  echo -e "${DIM}$1${RST}"
}

#------------------------------------------------------------------------------
# Retrieves the external IP of the given service
#------------------------------------------------------------------------------

function getExtIP {
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

function publish {

  # Get the external IP of the service
  local ip
  ip=$(getExtIP "${1}" "${2}" "${3}")

  # Setup socat for additional edge cases
  nohup socat TCP-LISTEN:"${4}",fork TCP:"${ip}":80 &> /dev/null & disown
}

#------------------------------------------------------------------------------
# Wait for all background jobs, fail if any failed
#------------------------------------------------------------------------------

function join {
  local pid status=0
  for pid in $(jobs -p); do wait "${pid}" || status=$?; done
  return "${status}"
}

#------------------------------------------------------------------------------
# Sum of RX+TX bytes across all non-loopback interfaces in this devcontainer
#------------------------------------------------------------------------------

function net_bytes {
  awk '/:/ && $1 !~ /^lo:/ { gsub(":", "", $1); rx += $2; tx += $10 }
       END { printf "%.0f", rx + tx }' /proc/net/dev
}

#------------------------------------------------------------------------------
# Format a byte count in human-readable IEC units (e.g. 1.2MiB)
#------------------------------------------------------------------------------

function human_bytes {
  numfmt --to=iec-i --suffix=B --format='%.1f' "${1:-0}"
}

#------------------------------------------------------------------------------
# Format a duration in seconds as "<m>m <s>s" (e.g. 5m 12s)
#------------------------------------------------------------------------------

function human_time {
  printf '%dm %ds' $(( ${1:-0} / 60 )) $(( ${1:-0} % 60 ))
}

#------------------------------------------------------------------------------
# Run a command and print its elapsed time and network traffic
#------------------------------------------------------------------------------

function measure {
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

function retry {
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
function k0 {
  kubectl --context "kind-${MNGR}" "${@}"
}

# Helper function h0
function h0 {
  retry helm --kube-context "kind-${MNGR}" "${@}"
}

#------------------------------------------------------------------------------
# Cluster IPs (lazy initialization)
#------------------------------------------------------------------------------

declare -gxA IP; IP_INIT=false

function ensure-ips {
  [[ "${IP_INIT}" == true ]] && return 0
  for CLUSTER in ${MNGR} $(list clusters wkld "${WLCNT}"); do
    IP[${CLUSTER}]=$(docker inspect "${CLUSTER}-control-plane" |
      jq -r '.[].NetworkSettings.Networks.kind.IPAddress')
  done; IP_INIT=true
}
