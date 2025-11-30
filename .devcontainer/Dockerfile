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
    && echo 'alias tf=terraform' >> /home/vscode/.bashrc \
    && echo 'alias ll="ls -alh"' >> /home/vscode/.bashrc

# Set working directory
WORKDIR /workspace

# Default command
CMD ["/bin/bash"]
