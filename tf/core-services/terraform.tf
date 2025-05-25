terraform {
  cloud {

    organization = "fzymgc-house"

    workspaces {
      name = "core-services"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "onepassword" {
  account = "OGRXP4CXIVAVXIQ2QBBL7ZOHWE"
}

provider "helm" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
}