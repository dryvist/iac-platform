output "organization_id" {
  description = "Terrakube organization id"
  value       = terrakube_organization.org.id
}

output "tofu_github_workspace_id" {
  description = "Workspace id for the tofu-github consumer"
  value       = terrakube_workspace_cli.tofu_github.id
}

output "workspace_ids" {
  description = "Workspace ids keyed by the fleet-wide Terrakube workspace name"
  value       = local.workspace_ids
}

output "desired_state_apply_template_id" {
  description = "Job template id for the desired-state gated apply workflow input"
  value       = try(terrakube_organization_template.this["desired_state_apply"].id, null)
}

output "clerk_team_name" {
  description = "Org-qualified name of the clerk team"
  value       = try(terrakube_team.clerk[0].name, null)
}

output "clerk_plan_apply_template_id" {
  description = "Job template id for the clerk-approved plan and apply workflow"
  value       = try(terrakube_organization_template.this["clerk_plan_apply"].id, null)
}
