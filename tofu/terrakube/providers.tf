# Workspaces-as-code for the Terrakube instance this repo deploys.
#
# Authentication: TERRAKUBE_ENDPOINT + TERRAKUBE_TOKEN environment variables
# (a Terrakube PAT from the UI, or a team token). Nothing here reads a keychain.
#
# State bootstrap sequence (chicken-and-egg, by design):
#   1. First applies run on LOCAL state (no backend block) — Terrakube can't
#      hold its own workspace definitions before it exists.
#   2. Once the instance is healthy and the `iac-platform` workspace exists,
#      uncomment the cloud block and `tofu init` to migrate state in.
#   Residual risk accepted: if Terrakube dies, workspace definitions are
#   re-applied from git on local state after a restore.
terraform {
  required_version = ">= 1.10"

  required_providers {
    terrakube = {
      # OpenTofu registry serves this provider under the project's legacy
      # namespace (azbuilder), tracking the same releases as
      # terrakube-io/terrakube on the Terraform registry.
      source  = "azbuilder/terrakube"
      version = "~> 0.24"
    }
  }

  # cloud {
  #   hostname     = "terrakube-api.<domain>"   # real FQDN from your env/notes
  #   organization = "dryvist"
  #   workspaces { name = "iac-platform" }
  # }
}

provider "terrakube" {}
