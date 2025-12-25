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
    && rm -rf /var/lib/apt/lists/*


# Install k3sup for cluster management
RUN curl -sLS https://get.k3sup.dev | sh

# Install HashiCorp Vault CLI
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list \
    && apt-get update && apt-get install -y vault \
    && rm -rf /var/lib/apt/lists/*

# Set up Python virtual environment directory
ENV VIRTUAL_ENV=/workspace/.venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Switch to vscode user
USER vscode

# Add helpful aliases
RUN echo 'alias k=kubectl' >> /home/vscode/.bashrc \
    && echo 'alias tf=terraform' >> /home/vscode/.bashrc \
    && echo 'alias ll="ls -alh"' >> /home/vscode/.bashrc

# Set working directory
WORKDIR /workspace

# Default command
CMD ["/bin/bash"]
