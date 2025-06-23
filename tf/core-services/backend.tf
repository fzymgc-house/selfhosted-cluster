terraform {
  cloud {
    organization = "fzymgc-house"
    workspaces {
      name = "main-cluster-core-services"
      project = "k8s-cluster"
    }
  }
}
