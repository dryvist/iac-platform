# Semaphore's object graph as code — the project, repositories, inventories,
# environments, templates and schedules that were previously a manual UI
# checklist in docs/runbook.md.
#
# Structured as a sibling of tofu/terrakube/: an application's internal state
# declared through its own REST API, with the API credential read ephemerally
# from OpenBao so it never lands in state.
terraform {
  required_version = ">= 1.11"

  required_providers {
    # Vendor namespace. The 0.3.x releases are cut by Semaphore's own author and
    # the provider is tested against the three most recent Semaphore minor lines
    # (v2.16-v2.18); the deployed pin is v2.18.18, inside that window. Bump the
    # provider and the server pin together, not independently.
    #
    # Known and accepted: the provider's README describes itself as
    # "AI-supported, not actively maintained", and its client is generated from
    # a patched copy of upstream's OpenAPI spec. The mitigation is the drift
    # audit in each resource file — every settable attribute is enumerated and
    # declared, so a server-side change surfaces as a plan diff rather than as
    # silent drift.
    semaphoreui = {
      source  = "semaphoreui/semaphore"
      version = "~> 0.3.9"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.10"
    }
  }

  # hostname and organization are intentionally omitted so no internal FQDN or
  # org login is committed to this public repo. OpenTofu reads them from
  # TF_CLOUD_HOSTNAME / TF_CLOUD_ORGANIZATION at run time.
  cloud {
    workspaces {
      name = "iac-platform-semaphore"
    }
  }
}

provider "vault" {
  skip_child_token = true
}

# The API token is minted by scripts/provision-semaphore-token.sh against the
# local break-glass admin. Read ephemerally: it is never written to state.
#
# secret/apps/<app>, not the platform subtree: this is an application
# credential, and `apps` is the tier the OpenBao access model actually grants a
# write leaf on. Storing it under `platform` would have required widening that
# model to write one field into a subtree deliberately kept read-only.
ephemeral "vault_kv_secret_v2" "semaphore" {
  mount = "secret"
  name  = "apps/semaphore"
}

provider "semaphoreui" {
  api_base_url = var.semaphore_api_base_url
  api_token    = ephemeral.vault_kv_secret_v2.semaphore.data.semaphore_api_token
}
