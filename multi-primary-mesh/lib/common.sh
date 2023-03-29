#!/usr/bin/env bash

# Cluster names
export CLUS0="kube-00"
export CLUS1="kube-01"
export CLUS2="kube-02"

# Define a stamp
export -A STAMP=(
  [name]="red-balloon"
  [clusters]="${CLUS1} ${CLUS2}"
)

export -A STAMPS=(
  [red-balloon]="${CLUS1} ${CLUS2}"
  #[pizza]="pizza-1 pizza-2"
)
