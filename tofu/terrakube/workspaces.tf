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

data "vault_kv_secret_v2" "terrakube_local_workspaces" {
  mount = "config"
  name  = "terrakube/local-workspaces"
}

locals {
  terrakube_local_workspaces = toset(jsondecode(nonsensitive(data.vault_kv_secret_v2.terrakube_local_workspaces.data_json)).workspaces)
}

data "terrakube_workspace" "local" {
  for_each = local.terrakube_local_workspaces

  name         = each.key
  organization = var.organization_name
}

resource "terrakube_workspace_cli" "local" {
  for_each = local.terrakube_local_workspaces

  organization_id = terrakube_organization.org.id
  name            = each.key
  description     = "Locally executed workspace"
  execution_mode  = "local"
  iac_type        = "tofu"
  iac_version     = var.tofu_version
}

resource "terrakube_workspace_cli" "tofu_github_org" {
  for_each = local.tofu_github_orgs

  organization_id = terrakube_organization.org.id
  name            = "tofu-github-${each.key}"
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
  workspace_ids = merge({
    iac-platform                = terrakube_workspace_cli.iac_platform.id
    iac-platform-semaphore      = terrakube_workspace_cli.iac_platform_semaphore.id
    tofu-github                 = terrakube_workspace_cli.tofu_github.id
    github-org-secrets          = terrakube_workspace_cli.github_org_secrets.id
    tofu-unifi                  = terrakube_workspace_cli.tofu_unifi.id
    tofu-aws-production         = terrakube_workspace_cli.tofu_aws_production.id
    tofu-runs-on                = terrakube_workspace_cli.tofu_runs_on.id
    tofu-proxmox                = terrakube_workspace_cli.tofu_proxmox.id
    tofu-proxmox-aws-infra      = terrakube_workspace_cli.tofu_proxmox_aws_infra.id
    tofu-proxmox-servarr-config = terrakube_workspace_cli.tofu_proxmox_servarr_config.id
    }, {
    for org, workspace in terrakube_workspace_cli.tofu_github_org : "tofu-github-${org}" => workspace.id
  })
}


# OpenTofu 1.7+ supports for_each in import blocks:
# https://opentofu.org/docs/v1.7/language/import/
import {
  for_each = local.terrakube_local_workspaces
  to       = terrakube_workspace_cli.local[each.key]
  id       = "${terrakube_organization.org.id},${data.terrakube_workspace.local[each.key].id}"
}
