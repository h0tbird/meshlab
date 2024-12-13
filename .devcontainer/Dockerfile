FROM mcr.microsoft.com/devcontainers/base:bullseye

# Install base packages
RUN apt-get update && \
    install -m 0755 -d /etc/apt/keyrings && \
    apt-get install -y apt-transport-https ca-certificates curl gnupg jq

# Install kubectl repo
RUN VERSION="v1.32" && \
    curl -fsSL https://pkgs.k8s.io/core:/stable:/${VERSION}/deb/Release.key | \
    gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg && \
    chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${VERSION}/deb/ /" \
    >> /etc/apt/sources.list.d/kubernetes.list && \
    chmod 644 /etc/apt/sources.list.d/kubernetes.list

# Install helm
RUN VERSION="v3.16.3" && \
    curl -fsSLo /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 && \
    chmod 700 /tmp/get_helm.sh && /tmp/get_helm.sh --version ${VERSION} && rm -f /tmp/get_helm.sh

# Install yq
RUN VERSION="v4.44.6" && ARCH=$(dpkg --print-architecture) && \
    wget https://github.com/mikefarah/yq/releases/download/${VERSION}/yq_linux_${ARCH} -O /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

# Install argocd
RUN VERSION="v2.13.2" && ARCH=$(dpkg --print-architecture) && \
    wget https://github.com/argoproj/argo-cd/releases/download/${VERSION}/argocd-linux-${ARCH} -O /usr/local/bin/argocd && \
    chmod +x /usr/local/bin/argocd

# Install argo
RUN VERSION="v3.6.2" && ARCH=$(dpkg --print-architecture) && \
    wget -qO- https://github.com/argoproj/argo-workflows/releases/download/${VERSION}/argo-linux-${ARCH}.gz | gunzip -c > /usr/local/bin/argo && \
    chmod +x /usr/local/bin/argo

# Install cilium-cli
RUN VERSION="v0.16.22" && ARCH=$(dpkg --print-architecture) && \
    wget -qO- https://github.com/cilium/cilium-cli/releases/download/${VERSION}/cilium-linux-${ARCH}.tar.gz | tar -xz -C /usr/local/bin/ && \
    chmod +x /usr/local/bin/cilium

# Install packages
RUN apt-get update && \
    apt-get install -y kubectl && \
    apt-get autoremove -y && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

# Create a symlink to kubectl
RUN ln -s /usr/local/bin/kubectl /usr/local/bin/k
