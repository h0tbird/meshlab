# See (https://mcr.microsoft.com/en-us/artifact/mar/devcontainers/base/about)
# See (https://github.com/devcontainers/images/tree/main/src/base-ubuntu)
FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Labels
LABEL "org.opencontainers.image.title"="Meshlab's devcontainer"
LABEL "org.opencontainers.image.description"="A devcontainer for Meshlab"
LABEL "org.opencontainers.image.source"="https://github.com/h0tbird/meshlab/tree/master/.devcontainer/Dockerfile"

# Environment variables
ENV LOCALE=en_US.UTF-8 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
ENV PATH=/workspaces/meshlab/bin:${PATH}

# Install base packages
RUN apt update && \
    apt install -y --no-install-recommends \
    curl jq gnupg iputils-ping dnsutils neovim \
    socat netcat-openbsd && \
    apt autoremove -y && apt clean -y && \
    rm -rf /var/lib/apt/lists/* && \
    chmod -x /etc/update-motd.d/*

# Set zsh as default shell
RUN chsh -s /usr/bin/zsh root && \
    chsh -s /usr/bin/zsh vscode && \
    echo 'export GPG_TTY=$(tty)' >> /etc/zsh/zshenv && \
    sed -i '/^ZSH_THEME/c\ZSH_THEME="robbyrussell"' /root/.zshrc && \
    sed -i '/^ZSH_THEME/c\ZSH_THEME="robbyrussell"' /home/vscode/.zshrc

# Install kind (https://github.com/kubernetes-sigs/kind/releases)
RUN VERSION="v0.31.0" && ARCH=$(dpkg --print-architecture) && \
    wget https://github.com/kubernetes-sigs/kind/releases/download/${VERSION}/kind-linux-${ARCH} -O /usr/local/bin/kind && \
    chmod +x /usr/local/bin/kind && echo "source <(kind completion zsh) && compdef _kind kind" >> /etc/zsh/zshrc

# Install kubectl (https://cdn.dl.k8s.io/release/stable.txt)
RUN VERSION="v1.35.0" && ARCH=$(dpkg --print-architecture) && \
    wget https://dl.k8s.io/release/${VERSION}/bin/linux/${ARCH}/kubectl -O /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl && ln -s /usr/local/bin/kubectl /usr/local/bin/k && \
    echo "source <(kubectl completion zsh) && compdef _kubectl kubectl" >> /etc/zsh/zshrc

# Install helm (https://github.com/helm/helm/releases)
RUN VERSION="v4.0.4" && \
    curl -fsSLo /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 && \
    chmod 700 /tmp/get_helm.sh && /tmp/get_helm.sh --version ${VERSION} && rm -f /tmp/get_helm.sh && \
    echo "source <(helm completion zsh) && compdef _helm helm" >> /etc/zsh/zshrc

# Install yq (https://github.com/mikefarah/yq/releases)
RUN VERSION="v4.50.1" && ARCH=$(dpkg --print-architecture) && \
    wget https://github.com/mikefarah/yq/releases/download/${VERSION}/yq_linux_${ARCH} -O /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq && echo "source <(yq completion zsh) && compdef _yq yq" >> /etc/zsh/zshrc

# Install argocd (https://github.com/argoproj/argo-cd/releases)
RUN VERSION="v3.2.2" && ARCH=$(dpkg --print-architecture) && \
    wget https://github.com/argoproj/argo-cd/releases/download/${VERSION}/argocd-linux-${ARCH} -qO /usr/local/bin/argocd && \
    chmod +x /usr/local/bin/argocd && echo "source <(argocd completion zsh) && compdef _argocd argocd" >> /etc/zsh/zshrc

# Install argo (https://github.com/argoproj/argo-workflows/releases)
RUN VERSION="v3.7.6" && ARCH=$(dpkg --print-architecture) && \
    wget -qO- https://github.com/argoproj/argo-workflows/releases/download/${VERSION}/argo-linux-${ARCH}.gz | gunzip -c > /usr/local/bin/argo && \
    chmod +x /usr/local/bin/argo && echo "source <(argo completion zsh) && compdef _argo argo" >> /etc/zsh/zshrc

# Install cilium-cli (https://github.com/cilium/cilium-cli/releases)
RUN VERSION="v0.18.9" && ARCH=$(dpkg --print-architecture) && \
    wget -qO- https://github.com/cilium/cilium-cli/releases/download/${VERSION}/cilium-linux-${ARCH}.tar.gz | tar -xz -C /usr/local/bin/ && \
    chmod +x /usr/local/bin/cilium && echo "source <(cilium completion zsh) && compdef _cilium cilium" >> /etc/zsh/zshrc

# Install istioctl (https://github.com/istio/istio/releases)
RUN VERSION="1.28.2" && ARCH=$(dpkg --print-architecture) && \
    curl -fsSLo /tmp/istio.tar.gz https://github.com/istio/istio/releases/download/${VERSION}/istio-${VERSION}-linux-${ARCH}.tar.gz && \
    tar -xC /usr/local/bin --strip-components 2 -f /tmp/istio.tar.gz istio-${VERSION}/bin/istioctl && rm -f /tmp/istio.tar.gz && \
    echo "source <(istioctl completion zsh) && compdef _istioctl istioctl" >> /etc/zsh/zshrc

# Install step (https://github.com/smallstep/cli/releases)
RUN VERSION="0.29.0" && ARCH=$(dpkg --print-architecture) && \
    wget -q https://dl.smallstep.com/gh-release/cli/gh-release-header/v${VERSION}/step-cli_${VERSION}-1_${ARCH}.deb && \
    dpkg -i step-cli_${VERSION}-1_${ARCH}.deb && rm -f step-cli_${VERSION}-1_${ARCH}.deb && \
    echo "source <(step completion zsh) && compdef _step step" >> /etc/zsh/zshrc

# Install gh (https://github.com/cli/cli/releases)
RUN VERSION="2.83.2" && ARCH=$(dpkg --print-architecture) && \
    curl -fsSLO https://github.com/cli/cli/releases/download/v${VERSION}/gh_${VERSION}_linux_${ARCH}.deb && \
    dpkg -i gh_${VERSION}_linux_${ARCH}.deb && rm -f gh_${VERSION}_linux_${ARCH}.deb && \
    echo "source <(gh completion -s zsh) && compdef _gh gh" >> /etc/zsh/zshrc

# Install mdbook (https://github.com/rust-lang/mdBook/releases)
RUN VERSION="v0.5.2" && ARCH=$(arch) && \
    curl -fsSL https://github.com/rust-lang/mdbook/releases/download/${VERSION}/mdbook-${VERSION}-${ARCH}-unknown-linux-musl.tar.gz | \
    tar -xzC /usr/local/bin mdbook && echo "source <(mdbook completions zsh) && compdef _mdbook mdbook" >> /etc/zsh/zshrc

# Install swarmctl (https://github.com/h0tbird/k-swarm/releases)
RUN VERSION="0.3.4" && ARCH=$(dpkg --print-architecture) && \
    wget -qO- https://github.com/h0tbird/k-swarm/releases/download/v${VERSION}/swarmctl_${VERSION}_linux_${ARCH}.tar.gz | tar -xz -C /usr/local/bin/ && \
    chmod +x /usr/local/bin/swarmctl && echo "source <(swarmctl completion zsh) && compdef _swarmctl swarmctl" >> /etc/zsh/zshrc

# Install btop (https://github.com/aristocratos/btop/releases)
RUN VERSION="1.4.5" && ARCH=$(arch) && \
    wget -qO- https://github.com/aristocratos/btop/releases/download/v${VERSION}/btop-${ARCH}-linux-musl.tbz | \
    tar -xjC /usr/local/bin --strip-components 3 -f - ./btop/bin/btop

# Install kiali-prepare-remote-cluster.sh (https://github.com/kiali/kiali)
RUN curl -sLo /usr/local/bin/kiali-prepare-remote-cluster.sh \
    https://raw.githubusercontent.com/kiali/kiali/master/hack/istio/multicluster/kiali-prepare-remote-cluster.sh && \
    chmod +x /usr/local/bin/kiali-prepare-remote-cluster.sh
