# Workspaces-as-code for the Terrakube instance this repo deploys.
#
# The self-hosted workspace receives OpenBao workload identity from Terrakube.
# Its API token remains at the native platform path and is read ephemerally.
terraform {
  required_version = ">= 1.11"

  required_providers {
    terrakube = {
      # OpenTofu registry serves this provider under the project's legacy
      # namespace (azbuilder), tracking the same releases as
      # terrakube-io/terrakube on the Terraform registry.
      source  = "azbuilder/terrakube"
      version = "~> 0.24"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.10"
    }
  }

  cloud {
    hostname     = "terrakube-api.jacobpevans.com"
    organization = "dryvist"

    workspaces {
      name = "iac-platform"
    }
  }
}

provider "vault" {}

ephemeral "vault_kv_secret_v2" "terrakube" {
  mount = "secret"
  name  = "platform/terrakube/main"
}

provider "terrakube" {
  endpoint = "https://terrakube-api.jacobpevans.com"
  token    = ephemeral.vault_kv_secret_v2.terrakube.data.TERRAKUBE_TOKEN
}
