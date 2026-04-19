# See (https://mcr.microsoft.com/en-us/artifact/mar/devcontainers/base/about)
# See (https://github.com/devcontainers/images/tree/main/src/base-ubuntu)
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Labels
LABEL "org.opencontainers.image.title"="Meshlab's devcontainer"
LABEL "org.opencontainers.image.description"="A devcontainer for Meshlab"
LABEL "org.opencontainers.image.source"="https://github.com/h0tbird/meshlab/tree/master/.devcontainer/Dockerfile"

# Environment variables
ENV LOCALE=en_US.UTF-8 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
ENV PATH=/workspaces/meshlab/bin:${PATH}

# Use bash with pipefail so failures in piped commands (curl | tar, etc.) are
# surfaced instead of silently ignored.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Shared curl flags for all downloads: fail loud on HTTP errors,
# follow redirects, and retry on transient/HTTP failures.
ENV CURL="curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 --connect-timeout 10"

# Architecture helper: archmap <arm64_value> <amd64_value>
# Exits non-zero on unsupported architectures so broken downloads fail loudly.
RUN printf '#!/bin/sh\ncase "$(arch)" in aarch64) echo "$1";; x86_64) echo "$2";; *) echo "archmap: unsupported arch $(arch)" >&2; exit 1;; esac\n' > /usr/local/bin/archmap && \
    chmod +x /usr/local/bin/archmap

# Install base packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl jq iputils-ping dnsutils neovim socat \
    netcat-openbsd apache2-utils shellcheck \
    python3 ripgrep locales && \
    locale-gen en_US.UTF-8 && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/* && \
    chmod -x /etc/update-motd.d/*

# Set zsh as default shell.
# DOCKER_API_VERSION is exported in /etc/zsh/zprofile (login shells only)
# rather than zshenv (every shell), and only when the docker socket exists,
# to avoid a curl on every interactive subshell startup.
RUN chsh -s /usr/bin/zsh root && \
    chsh -s /usr/bin/zsh vscode && \
    printf '%s\n' \
      'if [ -S /var/run/docker.sock ]; then' \
      '  export DOCKER_API_VERSION=$(curl -s --unix-socket /var/run/docker.sock http://localhost/version | jq -r .ApiVersion)' \
      'fi' >> /etc/zsh/zprofile && \
    sed -i '/^ZSH_THEME/c\ZSH_THEME="robbyrussell"' /root/.zshrc && \
    sed -i '/^ZSH_THEME/c\ZSH_THEME="robbyrussell"' /home/vscode/.zshrc

# Define Docker functions (functions work better with completion than aliases)
RUN echo 'dind() { docker -H unix:///var/run/docker.sock "$@" }' >> /etc/zsh/zshrc && \
    echo 'dood() { docker -H unix:///var/run/docker-host.sock "$@" }' >> /etc/zsh/zshrc && \
    echo "source <(docker completion zsh)" >> /etc/zsh/zshrc && \
    echo "compdef _docker dind dood" >> /etc/zsh/zshrc

# Enable zsh completion for the meshlab CLI (bin/meshlab)
RUN echo "source <(meshlab completion zsh)" >> /etc/zsh/zshrc

# Install Go (https://go.dev/dl/)
RUN VERSION="1.26.2" && ARCH=$(archmap 'arm64' 'amd64') && \
    $CURL https://go.dev/dl/go${VERSION}.linux-${ARCH}.tar.gz | tar -xzC /usr/local && \
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/zsh/zshenv && \
    echo 'export PATH=$PATH:$HOME/go/bin' >> /etc/zsh/zshenv

# Install kind (https://github.com/kubernetes-sigs/kind/releases)
RUN VERSION="v0.31.0" && ARCH=$(archmap 'arm64' 'amd64') && \
    $CURL -o /usr/local/bin/kind https://github.com/kubernetes-sigs/kind/releases/download/${VERSION}/kind-linux-${ARCH} && \
    chmod +x /usr/local/bin/kind && echo "source <(kind completion zsh)" >> /etc/zsh/zshrc

# Install kubectl (https://cdn.dl.k8s.io/release/stable.txt)
RUN VERSION="v1.35.3" && ARCH=$(archmap 'arm64' 'amd64') && \
    $CURL -o /usr/local/bin/kubectl https://dl.k8s.io/release/${VERSION}/bin/linux/${ARCH}/kubectl && \
    chmod +x /usr/local/bin/kubectl && ln -s /usr/local/bin/kubectl /usr/local/bin/k && \
    echo "source <(kubectl completion zsh)" >> /etc/zsh/zshrc

# Install helm (https://github.com/helm/helm/releases)
RUN VERSION="v4.1.4" && \
    $CURL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/${VERSION}/scripts/get-helm-4 && \
    chmod 700 /tmp/get_helm.sh && /tmp/get_helm.sh --version ${VERSION} && rm -f /tmp/get_helm.sh && \
    echo "source <(helm completion zsh)" >> /etc/zsh/zshrc

# Install yq (https://github.com/mikefarah/yq/releases)
RUN VERSION="v4.52.5" && ARCH=$(archmap 'arm64' 'amd64') && \
    $CURL -o /usr/local/bin/yq https://github.com/mikefarah/yq/releases/download/${VERSION}/yq_linux_${ARCH} && \
    chmod +x /usr/local/bin/yq && echo "source <(yq completion zsh)" >> /etc/zsh/zshrc

# Install argocd (https://github.com/argoproj/argo-cd/releases)
RUN VERSION="v3.3.6" && ARCH=$(archmap 'arm64' 'amd64') && \
    $CURL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/${VERSION}/argocd-linux-${ARCH} && \
    chmod +x /usr/local/bin/argocd && echo "source <(argocd completion zsh)" >> /etc/zsh/zshrc

# Install argo (https://github.com/argoproj/argo-workflows/releases)
RUN VERSION="v4.0.4" && ARCH=$(archmap 'arm64' 'amd64') && \
    $CURL https://github.com/argoproj/argo-workflows/releases/download/${VERSION}/argo-linux-${ARCH}.gz | gunzip -c > /usr/local/bin/argo && \
    chmod +x /usr/local/bin/argo && echo "source <(argo completion zsh)" >> /etc/zsh/zshrc

# Install cilium-cli (https://github.com/cilium/cilium-cli/releases)
RUN VERSION="v0.19.2" && ARCH=$(archmap 'arm64' 'amd64') && \
    $CURL https://github.com/cilium/cilium-cli/releases/download/${VERSION}/cilium-linux-${ARCH}.tar.gz | tar -xz -C /usr/local/bin/ && \
    chmod +x /usr/local/bin/cilium && echo "source <(cilium completion zsh)" >> /etc/zsh/zshrc

# Install istioctl (https://github.com/istio/istio/releases)
RUN VERSION="1.29.2" && ARCH=$(archmap 'arm64' 'amd64') && \
    $CURL -o /tmp/istio.tar.gz https://github.com/istio/istio/releases/download/${VERSION}/istio-${VERSION}-linux-${ARCH}.tar.gz && \
    tar -xC /usr/local/bin --strip-components 2 -f /tmp/istio.tar.gz istio-${VERSION}/bin/istioctl && rm -f /tmp/istio.tar.gz && \
    echo "source <(istioctl completion zsh)" >> /etc/zsh/zshrc

# Install step (https://github.com/smallstep/cli/releases)
RUN VERSION="0.30.2" && ARCH=$(archmap 'arm64' 'amd64') && cd /tmp && \
    $CURL -O https://dl.smallstep.com/gh-release/cli/gh-release-header/v${VERSION}/step-cli_${VERSION}-1_${ARCH}.deb && \
    dpkg -i step-cli_${VERSION}-1_${ARCH}.deb && rm -f step-cli_${VERSION}-1_${ARCH}.deb && \
    echo "source <(step completion zsh)" >> /etc/zsh/zshrc

# Install gh (https://github.com/cli/cli/releases)
RUN VERSION="2.89.0" && ARCH=$(archmap 'arm64' 'amd64') && cd /tmp && \
    $CURL -O https://github.com/cli/cli/releases/download/v${VERSION}/gh_${VERSION}_linux_${ARCH}.deb && \
    dpkg -i gh_${VERSION}_linux_${ARCH}.deb && rm -f gh_${VERSION}_linux_${ARCH}.deb && \
    echo "source <(gh completion -s zsh)" >> /etc/zsh/zshrc

# Install mdbook (https://github.com/rust-lang/mdBook/releases)
RUN VERSION="v0.5.2" && ARCH=$(archmap 'aarch64' 'x86_64') && \
    $CURL https://github.com/rust-lang/mdbook/releases/download/${VERSION}/mdbook-${VERSION}-${ARCH}-unknown-linux-musl.tar.gz | \
    tar -xzC /usr/local/bin mdbook && echo "source <(mdbook completions zsh)" >> /etc/zsh/zshrc

# Install swarmctl (https://github.com/h0tbird/k-swarm/releases)
RUN VERSION="0.3.7" && ARCH=$(archmap 'arm64' 'amd64') && \
    $CURL https://github.com/h0tbird/k-swarm/releases/download/v${VERSION}/swarmctl_${VERSION}_linux_${ARCH}.tar.gz | \
    tar -xzC /usr/local/bin swarmctl && echo "source <(swarmctl completion zsh)" >> /etc/zsh/zshrc

# Install btop (https://github.com/aristocratos/btop/releases)
RUN VERSION="1.4.6" && ARCH=$(archmap 'aarch64' 'x86_64') && \
    $CURL https://github.com/aristocratos/btop/releases/download/v${VERSION}/btop-${ARCH}-unknown-linux-musl.tbz | \
    tar -xjC /usr/local/bin --strip-components 3 -f - ./btop/bin/btop

# Install tilt (https://github.com/tilt-dev/tilt/releases)
RUN VERSION="0.37.1" && ARCH=$(archmap 'arm64' 'x86_64') && \
    $CURL https://github.com/tilt-dev/tilt/releases/download/v${VERSION}/tilt.${VERSION}.linux.${ARCH}.tar.gz | \
    tar -xzC /usr/local/bin tilt && echo "source <(tilt completion zsh)" >> /etc/zsh/zshrc

# Install crane (https://github.com/google/go-containerregistry/releases)
RUN VERSION="v0.21.5" && ARCH=$(archmap 'arm64' 'x86_64') && \
    $CURL https://github.com/google/go-containerregistry/releases/download/${VERSION}/go-containerregistry_Linux_${ARCH}.tar.gz | \
    tar -xzC /usr/local/bin crane && echo "source <(crane completion zsh)" >> /etc/zsh/zshrc

# Install grafanactl (https://github.com/grafana/grafanactl/releases)
RUN VERSION="v0.1.9" && ARCH=$(archmap 'arm64' 'x86_64') && \
    $CURL https://github.com/grafana/grafanactl/releases/download/${VERSION}/grafanactl_Linux_${ARCH}.tar.gz | \
    tar -xzC /usr/local/bin grafanactl && echo "source <(grafanactl completion zsh)" >> /etc/zsh/zshrc

# Install bat (https://github.com/sharkdp/bat/releases)
RUN VERSION="0.26.1" && ARCH=$(archmap 'aarch64' 'x86_64') && \
    $CURL https://github.com/sharkdp/bat/releases/download/v${VERSION}/bat-v${VERSION}-${ARCH}-unknown-linux-musl.tar.gz | \
    tar -xzC /usr/local/bin --strip-components 1 -f - bat-v${VERSION}-${ARCH}-unknown-linux-musl/bat

# Install kiali-prepare-remote-cluster.sh (https://github.com/kiali/kiali)
RUN $CURL -o /usr/local/bin/kiali-prepare-remote-cluster.sh \
    https://raw.githubusercontent.com/kiali/kiali/master/hack/istio/multicluster/kiali-prepare-remote-cluster.sh && \
    chmod +x /usr/local/bin/kiali-prepare-remote-cluster.sh
