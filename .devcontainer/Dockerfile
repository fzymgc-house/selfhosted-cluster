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
    curl \
    wget \
    unzip \
    # Network tools
    netcat-openbsd \
    dnsutils \
    iputils-ping \
    # Utilities
    jq \
    yq \
    vim \
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
    # For direnv
    direnv \
    && rm -rf /var/lib/apt/lists/*

# Install 1Password CLI
RUN curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
    gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
    tee /etc/apt/sources.list.d/1password.list \
    && mkdir -p /etc/debsig/policies/AC2D62742012EA22/ \
    && curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol | \
    tee /etc/debsig/policies/AC2D62742012EA22/1password.pol \
    && mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22 \
    && curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
    gpg --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg \
    && apt-get update && apt-get install -y 1password-cli \
    && rm -rf /var/lib/apt/lists/*

# Install k3sup for cluster management
RUN curl -sLS https://get.k3sup.dev | sh

# Set up Python virtual environment directory
ENV VIRTUAL_ENV=/workspace/.venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Switch to vscode user
USER vscode

# Configure direnv for the vscode user
RUN echo 'eval "$(direnv hook bash)"' >> /home/vscode/.bashrc

# Add helpful aliases
RUN echo 'alias k=kubectl' >> /home/vscode/.bashrc \
    && echo 'alias kc="kubectl --context fzymgc-house"' >> /home/vscode/.bashrc \
    && echo 'alias tf=terraform' >> /home/vscode/.bashrc \
    && echo 'alias ll="ls -alh"' >> /home/vscode/.bashrc

# Set working directory
WORKDIR /workspace

# Default command
CMD ["/bin/bash"]
