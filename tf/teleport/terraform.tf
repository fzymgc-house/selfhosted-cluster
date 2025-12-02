terraform {
  cloud {
    organization = "fzymgc-house"
    workspaces {
      tags = ["main-cluster", "teleport"]
    }
  }
}

provider "teleport" {
  addr               = "teleport.fzymgc.house:443"
  identity_file_path = var.teleport_identity_file
}

provider "vault" {
  address = "https://vault.fzymgc.house"
}
