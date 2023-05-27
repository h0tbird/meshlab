# Introduction

Welcome to the MeshLab repository! In this lab, I have created a setup to validate Istio configurations in a cell-based architecture.
Each cell is an architecture block representing a unit of isolation and scalability.
The lab defines two cells, named `pasta` and `pizza`, each composed of two clusters.
Each cluster is configured with a multi-primary Istio control-plane for high availability and resilience.

Although the cells share the same root CA for their cryptographic material, each one uses a different SPIFFE trustDomain and each cluster within a cell has its own intermediate CA.
Locality failover is possible within the clusters of a cell, and all mTLS cross-cluster traffic flows through east-west Istio gateways because pod networks have non-routable CIDRs.

The purpose of this lab is to test and validate different Istio configurations in a realistic environment.
This lab can be useful for anyone who wants to learn Istio or wants to validate Istio configuration in a complex environment.

Feel free to explore the code and documentation in this repository, and if you have any questions or feedback, don't hesitate to reach out.

## Quick Start

```bash
./bin/launch # Deploy the lab
./bin/delete # Destroy the lab
./bin/argocd # Print ArgoCD details
```

## Other related repos

ArgoCD is used to deploy:
- [https://github.com/h0tbird/istio](https://github.com/h0tbird/istio)
- [https://github.com/h0tbird/httpbin](https://github.com/h0tbird/httpbin)
