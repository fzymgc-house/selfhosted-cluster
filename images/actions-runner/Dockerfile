# SPDX-License-Identifier: MIT
# Custom GitHub Actions runner with internal CA certificates and pre-installed tools
# https://github.com/fzymgc-house/selfhosted-cluster/issues/220

ARG RUNNER_VERSION=2.330.0
FROM ghcr.io/actions/actions-runner:${RUNNER_VERSION}

USER root

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    gnupg \
    lsb-release \
    jq \
    libcap2-bin \
    && rm -rf /var/lib/apt/lists/*

# Install HashiCorp Vault CLI
# Note: setcap -r removes IPC_LOCK capability that causes "Operation not permitted" in containers
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
      | tee /etc/apt/sources.list.d/hashicorp.list \
    && apt-get update && apt-get install -y vault \
    && setcap -r /usr/bin/vault \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Add CA certificates
COPY certs/*.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates

USER runner
