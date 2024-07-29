#!/usr/bin/env bash

#------------------------------------------------------------------------------
# Define cells and clusters
#------------------------------------------------------------------------------

export MNGR="kube-00"

export -A CELLS=(
  [pasta]="pasta-1 pasta-2"
  [pizza]="pizza-1 pizza-2"
)

export -A CLUSTERS=(
  [kube-00_podsubnet]="10.42.0.0/16"
  [pasta-1_podsubnet]="10.42.0.0/16" [pasta-2_podsubnet]="10.42.0.0/16"
  [pizza-1_podsubnet]="10.42.0.0/16" [pizza-2_podsubnet]="10.42.0.0/16"
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
      [ "${2:-cell}" == "all" ] && echo -n "${MNGR} "
      for CELL in "${!CELLS[@]}"; do
        echo -n "${CELLS[${CELL}]} "
      done ;;
  esac
}

#------------------------------------------------------------------------------
# Prints the given string in turquoise
#------------------------------------------------------------------------------

function blue {
  echo -e "\n\e[1;36m$1\e[0m\n"
}
