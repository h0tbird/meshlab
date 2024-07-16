# ArgoCD

[ArgoCD](https://argo-cd.readthedocs.io/en/stable/) is a GitOps platform for Kubernetes applications that enables continuous delivery with declarative management and automation of deployments from Git repositories to multiple clusters. With its user-friendly interface, robust features, and deep Kubernetes integration, ArgoCD is a popular choice for automating application delivery.

List all the applications:
```console
argocd app list
```

Manually sync applications:
```console
argocd app sync -l name=istio-issuers --async
argocd app sync -l name=istio-base --async
argocd app sync -l name=istio-cni --async
argocd app sync -l name=istio-istiod --async
argocd app sync -l name=istio-nsgw --async
argocd app sync -l name=istio-ewgw --async
```
