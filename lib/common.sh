#!/usr/bin/env bash

#------------------------------------------------------------------------------
# Define cells and clusters
#------------------------------------------------------------------------------

export MNGR="kube-00"

export -A CELLS=(
  [mngr]="kube-00"
  [pasta]="pasta-1 pasta-2"
  #[pizza]="pizza-1 pizza-2"
)

#------------------------------------------------------------------------------
# List cells and clusters
#------------------------------------------------------------------------------

function list {
  case $1 in
    "cells")
      for CELL in "${!CELLS[@]}"; do
        echo -n "${CELL} "
      done ;;
    "clusters")
      for CELL in "${!CELLS[@]}"; do
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
