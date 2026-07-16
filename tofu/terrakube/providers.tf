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
      #
      # Pinned below the RBAC-v2 releases (0.23+): those client versions
      # unconditionally send planJob/approveJob/role team attributes that
      # the deployed Terrakube server does not yet accept (server-side RBAC
      # v2 support lags the client). 0.22.x is the newest release whose team
      # resource still speaks the attribute set the deployed server expects.
      # Bump once the server accepts the newer attributes.
      source  = "azbuilder/terrakube"
      version = "~> 0.24.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.10"
    }
  }

  # hostname and organization are intentionally omitted so no internal FQDN
  # or org login is committed to this public repo. OpenTofu reads them from
  # TF_CLOUD_HOSTNAME / TF_CLOUD_ORGANIZATION at run time.
  cloud {
    workspaces {
      name = "iac-platform"
    }
  }
}

provider "vault" {
  skip_child_token = true
}

ephemeral "vault_kv_secret_v2" "terrakube" {
  mount = "secret"
  name  = "platform/terrakube/main"
}

provider "terrakube" {
  endpoint = var.terrakube_endpoint
  token    = ephemeral.vault_kv_secret_v2.terrakube.data.TERRAKUBE_TOKEN
}
