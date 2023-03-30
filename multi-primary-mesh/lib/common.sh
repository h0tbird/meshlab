#!/usr/bin/env bash

# Cluster names
export CLUS0="kube-00"
export CLUS1="pasta-1"
export CLUS2="pasta-2"

export -A STAMPS=(
  [pasta]="${CLUS1} ${CLUS2}"
  [pizza]="pizza-1 pizza-2"
)
