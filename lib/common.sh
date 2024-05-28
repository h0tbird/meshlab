#!/usr/bin/env bash

#------------------------------------------------------------------------------
# Define stamps and clusters
#------------------------------------------------------------------------------

export MNGR="kube-00"

export -A STAMPS=(
  [pasta]="pasta-1 pasta-2"
  [pizza]="pizza-1 pizza-2"
)

#------------------------------------------------------------------------------
# List clusters and stamps
#------------------------------------------------------------------------------

function list {
  case $1 in
    "clusters")
      [ "${2:-stamp}" == "all" ] && echo -n "${MNGR} "
      for STAMP in "${!STAMPS[@]}"; do
        echo -n "${STAMPS[${STAMP}]} "
      done ;;
    "stamps")
      for STAMP in "${!STAMPS[@]}"; do
        echo -n "${STAMP} "
      done ;;
  esac
}

#------------------------------------------------------------------------------
# Prints the given string in turquoise
#------------------------------------------------------------------------------

function blue {
  echo -e "\n\e[1;36m$1\e[0m\n"
}
