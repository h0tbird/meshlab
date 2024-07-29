#!/usr/bin/env bash

#------------------------------------------------------------------------------
# Define cells and clusters
#------------------------------------------------------------------------------

export MNGR="kube-00"

export -A CELLS=(
  [pasta]="pasta-1 pasta-2"
  #[pizza]="pizza-1 pizza-2"
)

#------------------------------------------------------------------------------
# List clusters and cells
#------------------------------------------------------------------------------

function list {
  case $1 in
    "clusters")
      [ "${2:-cell}" == "all" ] && echo -n "${MNGR} "
      for CELL in "${!CELLS[@]}"; do
        echo -n "${CELLS[${CELL}]} "
      done ;;
    "cells")
      for CELL in "${!CELLS[@]}"; do
        echo -n "${CELL} "
      done ;;
  esac
}

#------------------------------------------------------------------------------
# Prints the given string in turquoise
#------------------------------------------------------------------------------

function blue {
  echo -e "\n\e[1;36m$1\e[0m\n"
}
