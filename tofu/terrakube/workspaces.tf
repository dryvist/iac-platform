# One CLI-driven workspace per consuming repo. CLI-driven = the repo's own
# `tofu` (locally or in CI) talks to Terrakube via its cloud block; runs
# execute remotely on the executor; state lives in Terrakube (RustFS bucket).
# VCS-driven workspaces are deliberately not used: Terrakube is internal-only
# (no inbound webhooks) — GitHub Actions on self-hosted runners trigger runs.

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
