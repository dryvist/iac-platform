# Root-module inputs of the tofu-github workspace, declared here instead of set by hand.
locals {
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
