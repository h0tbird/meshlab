#!/usr/bin/env bash

#------------------------------------------------------------------------------
# Define cells and clusters
#------------------------------------------------------------------------------

export MNGR="mnger-1"
export DOMAIN="demo.lab"

export -A CELLS=(
  [mngr]=${MNGR}
  [pasta]="pasta-1 pasta-2"
  [pizza]="pizza-1 pizza-2"
)

#------------------------------------------------------------------------------
# List cells and clusters
#------------------------------------------------------------------------------

function list {
  case $1 in
    "cells")
      for CELL in "${!CELLS[@]}"; do
        [[ "${2:-all}" == "wkld" && "$CELL" == "mngr" ]] && continue
        echo -n "${CELL} "
      done ;;
    "clusters")
      for CELL in "${!CELLS[@]}"; do
        [[ "${2:-all}" == "wkld" && "$CELL" == "mngr" ]] && continue
        echo -n "${CELLS[${CELL}]} "
      done ;;
  esac
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

  # Setup prerouting rules
  iptables -t nat -C MESHLABPRE -p tcp --dport "${4}" -j DNAT --to-destination "${IP}":80 2>/dev/null || \
  iptables -t nat -A MESHLABPRE -p tcp --dport "${4}" -j DNAT --to-destination "${IP}":80

  # Setup postrouting rules
  iptables -t nat -C MESHLABPOS -p tcp -d "${IP}" --dport 80 -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A MESHLABPOS -p tcp -d "${IP}" --dport 80 -j MASQUERADE
}