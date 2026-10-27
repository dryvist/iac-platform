# Root-module inputs of the tofu-github workspace, declared here instead of set by hand.
data "vault_kv_secret_v2" "github_orgs" {
  mount = "config"
  name  = "github/orgs"
}

locals {
  tofu_github_orgs = toset(jsondecode(nonsensitive(data.vault_kv_secret_v2.github_orgs.data_json)).orgs)

  tofu_github_inputs = {
    github_owner = {
      value       = "dryvist"
      description = "GitHub organization managed by this workspace"
      hcl         = false
    }
    automation_bypass_app_ids = {
      value       = "[2740, 29110, 222410, 1144995, 1210556, 1236702, 2956476, 3509510, 3923580, 4241562, 4282473, 4952939]"
      description = "GitHub App IDs allowed to bypass automation rules"
      hcl         = true
    }
    org_branch_write_restriction_enforcement = {
      value       = "evaluate"
      description = "Organization branch-write restriction enforcement mode"
      hcl         = false
    }
    org_automerge_manual_enforcement = {
      value       = "active"
      description = "Organization manual-automerge enforcement mode"
      hcl         = false
    }
    dryvist_org_extras = {
      value       = "true"
      description = "Enable dryvist-only organization policies"
      hcl         = true
    }
  }

  # Per-org workspaces differ from dryvist only in these inputs.
  tofu_github_org_overrides = {
    org_automerge_manual_enforcement = "evaluate"
    dryvist_org_extras               = "false"
  }

  tofu_github_org_inputs = {
    for pair in setproduct(local.tofu_github_orgs, keys(local.tofu_github_inputs)) : "${pair[0]}:${pair[1]}" => {
      org         = pair[0]
      key         = pair[1]
      value       = pair[1] == "github_owner" ? pair[0] : lookup(local.tofu_github_org_overrides, pair[1], local.tofu_github_inputs[pair[1]].value)
      description = local.tofu_github_inputs[pair[1]].description
      hcl         = local.tofu_github_inputs[pair[1]].hcl
    }
  }
}

resource "terrakube_workspace_variable" "tofu_github_inputs" {
  for_each = local.tofu_github_inputs

  organization_id = terrakube_organization.org.id
  workspace_id    = terrakube_workspace_cli.tofu_github.id
  key             = each.key
  value           = each.value.value
  description     = each.value.description
  category        = "TERRAFORM"
  sensitive       = false
  hcl             = each.value.hcl
}

resource "terrakube_workspace_variable" "tofu_github_org_inputs" {
  for_each = local.tofu_github_org_inputs

  organization_id = terrakube_organization.org.id
  workspace_id    = terrakube_workspace_cli.tofu_github_org[each.value.org].id
  key             = each.value.key
  value           = each.value.value
  description     = each.value.description
  category        = "TERRAFORM"
  sensitive       = false
  hcl             = each.value.hcl
}

resource "terrakube_workspace_cli" "github_org_secrets" {
  organization_id = terrakube_organization.org.id
  name            = "github-org-secrets"
  description     = "GitHub organization Actions secrets from OpenBao"
  execution_mode  = "remote"
  iac_type        = "tofu"
  iac_version     = var.tofu_version
}
