terraform {
  cloud {
    organization = "fzymgc-house"
    workspaces {
      name = "main-cluster-vault"
      project = "k8s-cluster"
    }
  }
}
