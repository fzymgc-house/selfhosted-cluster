# Development container for self-hosted cluster management
# Based on Python 3.13 with all necessary tools for Terraform, Ansible, and Kubernetes

ARG PYTHON_VERSION=3.13
FROM mcr.microsoft.com/devcontainers/python:${PYTHON_VERSION}

# Install system dependencies
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    # Build tools
    build-essential \
    git \
    git-lfs \
    curl \
    wget \
    unzip \
    # Network tools
    netcat-openbsd \
    dnsutils \
    iputils-ping \
    # Utilities
    bc \
    less \
    tree \
    ca-certificates \
    gnupg \
    lsb-release \
    # SSH and crypto
    openssh-client \
    sshpass \
    # For Ansible
    libffi-dev \
    libssl-dev \
    python3-dev \
    # For onigurumacffi (ansible-navigator dependency)
    libonig-dev \
    && rm -rf /var/lib/apt/lists/*

# Add fzymgc PKI root CA to system trust store for Vault TLS verification
COPY .devcontainer/fzymgc-ca-bundle.crt /usr/local/share/ca-certificates/fzymgc-ca-bundle.crt
RUN update-ca-certificates


# Install k3sup for cluster management
RUN curl -sLS https://get.k3sup.dev | sh

# Install git-delta for better diffs
# Detect architecture and download appropriate binary
RUN ARCH=$(dpkg --print-architecture) \
    && DELTA_VERSION=$(curl -s https://api.github.com/repos/dandavison/delta/releases/latest | jq -r .tag_name) \
    && if [ "$ARCH" = "arm64" ]; then \
         DELTA_ARCH="aarch64-unknown-linux-gnu"; \
       else \
         DELTA_ARCH="x86_64-unknown-linux-gnu"; \
       fi \
    && curl -fsSL "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/delta-${DELTA_VERSION}-${DELTA_ARCH}.tar.gz" \
       | tar -xz -C /tmp \
    && mv /tmp/delta-*/delta /usr/local/bin/ \
    && rm -rf /tmp/delta-* \
    && delta --version

# Install HashiCorp Vault CLI
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list \
    && apt-get update && apt-get install -y vault \
    && rm -rf /var/lib/apt/lists/*

# Switch to vscode user
USER vscode

# Add helpful aliases
RUN echo 'alias k=kubectl' >> /home/vscode/.bashrc \
    && echo 'alias tf=terraform' >> /home/vscode/.bashrc \
    && echo 'alias ll="ls -alh"' >> /home/vscode/.bashrc

# Default command (workdir set by devcontainer.json)
CMD ["/bin/bash"]
