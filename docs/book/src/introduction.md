# Introduction

Welcome to the MeshLab repository! In this lab, you will find a setup to validate Istio configurations in a cell-based architecture. Each cell is an architecture block representing a unit of isolation and scalability. The lab defines two cells, named `pasta` and `pizza`, each composed of two clusters. Each cluster is configured with a multi-primary Istio control-plane for high availability and resilience.

Although the cells share the same root CA for their cryptographic material, each one uses a different SPIFFE trustDomain and each cluster within a cell has its own intermediate CA. Locality failover is possible within the clusters of a cell, and all mTLS cross-cluster traffic flows through east-west Istio gateways because pod networks have non-routable CIDRs.

The purpose of this lab is to test and validate different Istio configurations in a realistic environment.

ArgoCD is used to deploy:
- [https://github.com/h0tbird/istio](https://github.com/h0tbird/istio)
- [https://github.com/h0tbird/httpbin](https://github.com/h0tbird/httpbin)
