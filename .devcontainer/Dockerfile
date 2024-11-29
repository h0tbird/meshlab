FROM mcr.microsoft.com/devcontainers/base:bullseye

# Install base packages
RUN apt-get update \
    && install -m 0755 -d /etc/apt/keyrings \
    && apt-get install -y apt-transport-https ca-certificates curl gnupg

# Install kubectl repo
RUN KUBECTL_MINOR_VERSION=v1.31 \
    && curl -fsSL https://pkgs.k8s.io/core:/stable:/${KUBECTL_MINOR_VERSION}/deb/Release.key | \
      gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
    && chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KUBECTL_MINOR_VERSION}/deb/ /" \
      >> /etc/apt/sources.list.d/kubernetes.list \
    && chmod 644 /etc/apt/sources.list.d/kubernetes.list

# Install packages
RUN apt-get update \
    && apt-get install -y kubectl \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*
