# One CLI-driven workspace per consuming repo. CLI-driven = the repo's own
# `tofu` (locally or in CI) talks to Terrakube via its cloud block; runs
# execute remotely on the executor; state lives in Terrakube (RustFS bucket).
# VCS-driven workspaces are deliberately not used: Terrakube is internal-only
# (no inbound webhooks) — GitHub Actions on self-hosted runners trigger runs.
#
# Fully-declarative note (drift audit): terrakube_workspace_cli exposes exactly
# four settable attributes — description, execution_mode, iac_type, iac_version
# — and all four are declared below for every workspace. branch, folder,
# default_template and allow_remote_apply live ONLY on terrakube_workspace_vcs
# (the intentionally-unused VCS resource), so for CLI workspaces they are
# Terrakube-managed values, not configuration: every workspace reports the
# fixed `remote-content` branch sentinel and empty folder/template. There is
# therefore no git-branch setting to pin here — a CLI workspace plans against
# whatever content its own repo's CI uploads, not a tracked branch. Any per-
# workspace remote-apply flag is likewise set through the VCS resource only and
# cannot be codified while the CLI model (and the ~> 0.22 provider pin in
# providers.tf) is in force; revisit if a workspace migrates to VCS-driven.

# Existing consumer: dryvist/tofu-github (org governance as code).
resource "terrakube_workspace_cli" "tofu_github" {
  organization_id = terrakube_organization.org.id
  name            = "tofu-github"
  description     = "GitHub org governance as code (rulesets, labels, repo settings)"
  execution_mode  = "remote"
  iac_type        = "tofu"
  iac_version     = var.tofu_version
}

# Self-hosting workspace: this directory's own state migrates here once the
# instance is healthy (see providers.tf bootstrap note).
resource "terrakube_workspace_cli" "iac_platform" {
  organization_id = terrakube_organization.org.id
  name            = "iac-platform"
  description     = "Terrakube workspaces-as-code for this instance (self-hosted state)"
  execution_mode  = "remote"
  iac_type        = "tofu"
  iac_version     = var.tofu_version
}

# Semaphore's own object graph (tofu/semaphore/). Separate from the
# iac-platform workspace above because the two have different blast radii and
# different credentials: this one holds only Semaphore's project, repositories,
# inventories, templates and schedules, and authenticates to Semaphore's API
# rather than to Terrakube's.
resource "terrakube_workspace_cli" "iac_platform_semaphore" {
  organization_id = terrakube_organization.org.id
  name            = "iac-platform-semaphore"
  description     = "Semaphore project, repositories, inventories, templates and schedules"
  execution_mode  = "remote"
  iac_type        = "tofu"
  iac_version     = var.tofu_version
}

resource "terrakube_workspace_cli" "tofu_unifi" {
  organization_id = terrakube_organization.org.id
  name            = "tofu-unifi"
  description     = "UniFi network configuration and policy"
  execution_mode  = "remote"
  iac_type        = "tofu"
  iac_version     = var.tofu_version
}

resource "terrakube_workspace_cli" "tofu_aws_production" {
  organization_id = terrakube_organization.org.id
  name            = "tofu-aws-production"
  description     = "Production AWS infrastructure"
  execution_mode  = "remote"
  iac_type        = "tofu"
  iac_version     = var.tofu_version
}

resource "terrakube_workspace_cli" "tofu_runs_on" {
  organization_id = terrakube_organization.org.id
  name            = "tofu-runs-on"
  description     = "RunsOn infrastructure for self-hosted GitHub Actions runners"
  execution_mode  = "remote"
  iac_type        = "tofu"
  iac_version     = var.tofu_version
}

resource "terrakube_workspace_cli" "tofu_proxmox" {
  organization_id = terrakube_organization.org.id
  name            = "tofu-proxmox"
  description     = "Core Proxmox homelab infrastructure"
  execution_mode  = "remote"
  iac_type        = "tofu"
  iac_version     = var.tofu_version
}

resource "terrakube_workspace_cli" "tofu_proxmox_aws_infra" {
  organization_id = terrakube_organization.org.id
  name            = "tofu-proxmox-aws-infra"
  description     = "Public AWS and Route53 resources supporting the Proxmox homelab"
  execution_mode  = "remote"
  iac_type        = "tofu"
  iac_version     = var.tofu_version
}

resource "terrakube_workspace_cli" "tofu_proxmox_servarr_config" {
  organization_id = terrakube_organization.org.id
  name            = "tofu-proxmox-servarr-config"
  description     = "Servarr application configuration"
  execution_mode  = "remote"
  iac_type        = "tofu"
  iac_version     = var.tofu_version
}

locals {
  workspace_ids = {
    iac-platform                = terrakube_workspace_cli.iac_platform.id
    iac-platform-semaphore      = terrakube_workspace_cli.iac_platform_semaphore.id
    tofu-github                 = terrakube_workspace_cli.tofu_github.id
    tofu-unifi                  = terrakube_workspace_cli.tofu_unifi.id
    tofu-aws-production         = terrakube_workspace_cli.tofu_aws_production.id
    tofu-runs-on                = terrakube_workspace_cli.tofu_runs_on.id
    tofu-proxmox                = terrakube_workspace_cli.tofu_proxmox.id
    tofu-proxmox-aws-infra      = terrakube_workspace_cli.tofu_proxmox_aws_infra.id
    tofu-proxmox-servarr-config = terrakube_workspace_cli.tofu_proxmox_servarr_config.id
  }
}

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
  value           = "terrakube-${each.key}"
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
