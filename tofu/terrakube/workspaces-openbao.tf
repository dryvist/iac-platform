# OpenBao workload-identity variables set on every workspace that runs
# remotely through Terrakube (see workspaces.tf for the workspace definitions
# and the local.workspace_ids map this file iterates over).

# Terrakube exchanges its per-job signed identity for a short-lived OpenBao
# token. These four values are intentionally non-secret; the OpenBao JWT roles
# bind each role to the matching organization/workspace claims and decide which
# secrets that job may read. Provider credentials must not be stored as
# Terrakube workspace variables.
resource "terrakube_workspace_variable" "openbao_dynamic_credentials" {
  for_each = local.workspace_ids

  organization_id = terrakube_organization.org.id
  workspace_id    = each.value
  key             = "ENABLE_DYNAMIC_CREDENTIALS_VAULT"
  value           = "1"
  description     = "Enable Terrakube's native OpenBao workload identity exchange"
  category        = "ENV"
  sensitive       = false
  hcl             = false
}

resource "terrakube_workspace_variable" "openbao_audience" {
  for_each = local.workspace_ids

  organization_id = terrakube_organization.org.id
  workspace_id    = each.value
  key             = "WORKLOAD_IDENTITY_VAULT_AUDIENCE"
  value           = var.openbao_workload_audience
  description     = "Audience bound by this workspace's OpenBao JWT role"
  category        = "ENV"
  sensitive       = false
  hcl             = false
}

resource "terrakube_workspace_variable" "openbao_address" {
  for_each = local.workspace_ids

  organization_id = terrakube_organization.org.id
  workspace_id    = each.value
  key             = "VAULT_ADDR"
  value           = var.openbao_address
  description     = "Internal OpenBao HTTPS endpoint"
  category        = "ENV"
  sensitive       = false
  hcl             = false
}

resource "terrakube_workspace_variable" "openbao_role" {
  for_each = local.workspace_ids

  organization_id = terrakube_organization.org.id
  workspace_id    = each.value
  key             = "WORKLOAD_IDENTITY_VAULT_ROLE"
  value           = startswith(each.key, "tofu-github-") ? "terrakube-tofu-github" : "terrakube-${each.key}"
  description     = "Least-privilege OpenBao JWT role for this workspace"
  category        = "ENV"
  sensitive       = false
  hcl             = false
}

# Terrakube defaults the login mount to auth/jwt/login; the OpenBao JWT method
# is mounted at 'terrakube', so every workspace must override the path or the
# token exchange 404s and the run gets no VAULT_TOKEN.
resource "terrakube_workspace_variable" "openbao_auth_path" {
  for_each = local.workspace_ids

  organization_id = terrakube_organization.org.id
  workspace_id    = each.value
  key             = "WORKLOAD_IDENTITY_VAULT_AUTH_PATH"
  value           = var.openbao_workload_auth_path
  description     = "OpenBao JWT auth mount path this workspace logs into"
  category        = "ENV"
  sensitive       = false
  hcl             = false
}

# The semaphore workspace's root module takes openbao_address as a TERRAFORM
# variable and derives every endpoint from it. Terrakube does not forward a CLI
# -var or a local TF_VAR_* to a remote run, so the value must exist on the
# workspace itself or the run stops at input validation. Same non-secret value
# as VAULT_ADDR above, declared separately because the categories differ.
resource "terrakube_workspace_variable" "semaphore_openbao_address" {
  organization_id = terrakube_organization.org.id
  workspace_id    = terrakube_workspace_cli.iac_platform_semaphore.id
  key             = "openbao_address"
  value           = var.openbao_address
  description     = "Root input the Semaphore workspace derives its endpoints from"
  category        = "TERRAFORM"
  sensitive       = false
  hcl             = false
}

# Turns on the Semaphore schedules gated by the root's recurring_jobs_enabled
# variable. Set on the workspace for the same reason as openbao_address above.
resource "terrakube_workspace_variable" "semaphore_recurring_jobs_enabled" {
  organization_id = terrakube_organization.org.id
  workspace_id    = terrakube_workspace_cli.iac_platform_semaphore.id
  key             = "recurring_jobs_enabled"
  value           = "true"
  description     = "Enables the Semaphore schedules gated by recurring_jobs_enabled"
  category        = "TERRAFORM"
  sensitive       = false
  hcl             = false
}

# OpenTofu 1.7+ supports for_each in import blocks:
# https://opentofu.org/docs/v1.7/language/import/
import {
  to = terrakube_workspace_variable.openbao_auth_path["iac-platform"]
  id = "${terrakube_organization.org.id},1f848e6e-36c0-4299-954b-26faf56264f4,0eec3fc8-c4aa-483b-b066-fa14cf0050aa"
}
import {
  to = terrakube_workspace_variable.openbao_auth_path["tofu-aws-production"]
  id = "${terrakube_organization.org.id},57b6c19a-3472-41da-8530-2158a9d37ed5,75f3e964-0d15-49db-a7fb-26e441a11521"
}
import {
  to = terrakube_workspace_variable.openbao_auth_path["tofu-github"]
  id = "${terrakube_organization.org.id},41088d97-5b48-474f-ac2e-7364d60982bb,ba427b05-317c-443f-b725-fbb5ccff5257"
}
import {
  to = terrakube_workspace_variable.openbao_auth_path["tofu-proxmox"]
  id = "${terrakube_organization.org.id},c388c33f-26c9-4be0-bf23-be4669d56c58,887c9a83-6cda-4df4-8ca3-7e986750c5fa"
}
import {
  to = terrakube_workspace_variable.openbao_auth_path["tofu-proxmox-aws-infra"]
  id = "${terrakube_organization.org.id},381108db-8a4d-4401-b7e9-b5e198b2b161,bda5b44d-8716-4792-b4dc-ff21a55a0f60"
}
import {
  to = terrakube_workspace_variable.openbao_auth_path["tofu-proxmox-servarr-config"]
  id = "${terrakube_organization.org.id},3425119a-81bb-401b-8dba-878e264b59a0,b8311b2b-e626-4db9-9867-361e6d5b614e"
}
import {
  to = terrakube_workspace_variable.openbao_auth_path["tofu-runs-on"]
  id = "${terrakube_organization.org.id},aca29ad3-8691-406f-beee-c947ca3c24a4,77887178-e315-41ca-9d13-095182fe65b9"
}
import {
  to = terrakube_workspace_variable.openbao_auth_path["tofu-unifi"]
  id = "${terrakube_organization.org.id},acf68097-ed59-4fd7-9e74-ada045b5f18a,0f9accbd-680f-4808-8e3a-a1873c326f86"
}
