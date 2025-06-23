terraform {
  cloud {
    organization = "fzymgc-house"
    workspaces {
      project = "k8s-cluster"
      tags = ["main-cluster", "authentik"]
    }
  }
}
