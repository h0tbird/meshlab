#!/usr/bin/env bash

#------------------------------------------------------------------------------
# Define cells and clusters
#------------------------------------------------------------------------------

export MNGR="mnger-1"
export DOMAIN="demo.lab"

declare -A CELLS=(
  [mngr]=${MNGR}
  [pasta]="pasta-1 pasta-2"
  [pizza]="pizza-1 pizza-2"
)

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
  echo -e "\n\e[1;36m$1\e[0m\n"
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
