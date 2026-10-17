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
  value       = terrakube_organization_template.this["desired_state_apply"].id
}
