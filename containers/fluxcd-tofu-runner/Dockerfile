FROM hashicorp/terraform:latest AS terraform

FROM ghcr.io/flux-iac/tf-runner:latest

USER root
COPY --from=terraform /bin/terraform /usr/local/bin/terraform

USER 65532:65532
