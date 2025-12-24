provider "vault" {
  address = "https://vault.fzymgc.house"
}

terraform {
  backend "local" {}
}
