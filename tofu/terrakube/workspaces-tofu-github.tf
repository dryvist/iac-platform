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

  # Variables the root module no longer declares. Phase 2 deletes this map, the
  # resource and the import blocks below, so the next apply destroys them.
  tofu_github_retired = {
    agent_bypass_app_ids = {
      value     = "[2956476, 1236702, 4241562, 4952939, 1144995, 1210556]"
      category  = "TERRAFORM"
      sensitive = false
      hcl       = true
    }
    triage_merge_app_ids = {
      value     = "[3923580]"
      category  = "TERRAFORM"
      sensitive = false
      hcl       = true
    }
    GITHUB_TOKEN = {
      value     = ""
      category  = "ENV"
      sensitive = true
      hcl       = false
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

resource "terrakube_workspace_variable" "tofu_github_retired" {
  for_each = local.tofu_github_retired

  organization_id = terrakube_organization.org.id
  workspace_id    = terrakube_workspace_cli.tofu_github.id
  key             = each.key
  value           = each.value.value
  description     = "Retired; deleted by the next change"
  category        = each.value.category
  sensitive       = each.value.sensitive
  hcl             = each.value.hcl

  lifecycle {
    ignore_changes = [value, description]
  }
}

import {
  to = terrakube_workspace_variable.tofu_github_inputs["automation_bypass_app_ids"]
  id = "${terrakube_organization.org.id},41088d97-5b48-474f-ac2e-7364d60982bb,c915beb2-4d04-4e95-81af-8314d595f638"
}

import {
  to = terrakube_workspace_variable.tofu_github_inputs["org_branch_write_restriction_enforcement"]
  id = "${terrakube_organization.org.id},41088d97-5b48-474f-ac2e-7364d60982bb,4bac4d42-5c4f-4021-9c26-e652a5275503"
}

import {
  to = terrakube_workspace_variable.tofu_github_inputs["org_automerge_manual_enforcement"]
  id = "${terrakube_organization.org.id},41088d97-5b48-474f-ac2e-7364d60982bb,39690938-b56a-452d-bcfc-1e02b6269939"
}

import {
  to = terrakube_workspace_variable.tofu_github_retired["agent_bypass_app_ids"]
  id = "${terrakube_organization.org.id},41088d97-5b48-474f-ac2e-7364d60982bb,70cb3944-85b6-4256-87b8-ea14f753c3cb"
}

import {
  to = terrakube_workspace_variable.tofu_github_retired["triage_merge_app_ids"]
  id = "${terrakube_organization.org.id},41088d97-5b48-474f-ac2e-7364d60982bb,f3822e23-2cae-4044-9a17-53daf3257f58"
}

import {
  to = terrakube_workspace_variable.tofu_github_retired["GITHUB_TOKEN"]
  id = "${terrakube_organization.org.id},41088d97-5b48-474f-ac2e-7364d60982bb,d37fc08a-c6d9-41dc-8433-702fca2bcf49"
}
