#!/usr/bin/env bash

#------------------------------------------------------------------------------
# Define stamps and clusters
#------------------------------------------------------------------------------

export CLUS0="kube-00"
export CLUS1="pasta-1"
export CLUS2="pasta-2"

export -A STAMPS=(
  [pasta]="${CLUS1} ${CLUS2}"
  [pizza]="pizza-1 pizza-2"
)

#------------------------------------------------------------------------------
# List clusters and stamps
#------------------------------------------------------------------------------

function list {
  case $1 in
    "clusters")
      [ "${2:-stamp}" == "all" ] && echo -n "${CLUS0} "
      for STAMP in "${!STAMPS[@]}"; do
        echo -n "${STAMPS[${STAMP}]} "
      done ;;
    "stamps")
      for STAMP in "${!STAMPS[@]}"; do
        echo -n "${STAMP} "
      done ;;
  esac
}