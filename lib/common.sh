#!/usr/bin/env bash

#------------------------------------------------------------------------------
# Variables
#------------------------------------------------------------------------------

export MNGR="mnger-1"
export DOMAIN="demo.lab"

# Define cells and clusters
declare -A CELLS=(
  [mngr]=${MNGR}
  [pasta]="pasta-1 pasta-2"
  [pizza]="pizza-1 pizza-2"
)

# One password to rule them all
PWD='meshlab123'

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
  kubectl --context="kind-${1}" -n "${2}" get svc "${3}" -o yaml | \
  yq '.status.loadBalancer.ingress[0].ip'
}

#------------------------------------------------------------------------------
# Publishes the given service in the given VM port
#------------------------------------------------------------------------------

function publish {

  # Get the external IP of the service
  IP=$(getExtIP "${1}" "${2}" "${3}")

  # Setup socat for additional edge cases
  nohup socat TCP-LISTEN:"${4}",fork TCP:"${IP}":80 &> /dev/null & disown
}

#------------------------------------------------------------------------------
# Wait for all background jobs, fail if any failed
#------------------------------------------------------------------------------

function join { for pid in $(jobs -p); do wait "${pid}"; done; }

#------------------------------------------------------------------------------
# Run a command and print its elapsed time
#------------------------------------------------------------------------------

function timed {
  local t=${SECONDS}; "$@"
  grey "  └── done in $((SECONDS - t))s"
}

#------------------------------------------------------------------------------
# Retry til success
#------------------------------------------------------------------------------

function retry { until "$@"; do sleep 2; done; }

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

declare -gA IP; IP_INIT=false

function ensure-ips {
  [[ "${IP_INIT}" == true ]] && return 0
  for CLUSTER in $(list clusters all "${WLCNT}"); do
    IP[${CLUSTER}]=$(docker inspect "${CLUSTER}-control-plane" |
      jq -r '.[].NetworkSettings.Networks.kind.IPAddress')
  done; IP_INIT=true
}
