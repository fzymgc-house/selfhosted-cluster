provider "onepassword" {
  account = "OGRXP4CXIVAVXIQ2QBBL7ZOHWE"
}

terraform {
  cloud {
    organization = "fzymgc-house"
    workspaces {
      tags = ["main-cluster", "authentik"]
    }
  }
}