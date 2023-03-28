#!/usr/bin/env bash

# Cluster names
export CLUS0="kube-00"
export CLUS1="kube-01"
export CLUS2="kube-02"

# Define a stamp
export -A STAMP=(
  [name]="red-ballon"
  [clusters]="${CLUS1} ${CLUS2}"
)
