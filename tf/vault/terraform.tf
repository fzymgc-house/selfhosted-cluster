terraform {
  cloud {
    organization = "fzymgc-house"
    workspaces {
      tags = ["main-cluster", "vault"]
    }
  }
}

provider "onepassword" {
  account = "OGRXP4CXIVAVXIQ2QBBL7ZOHWE"
}
