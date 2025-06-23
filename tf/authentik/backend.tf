terraform {
  cloud {
    organization = "fzymgc-house"
    workspaces {
      name = "main-cluster-authentik"
      project = "k8s-cluster"
    }
  }
}
