output "organization_id" {
  description = "Terrakube organization id"
  value       = terrakube_organization.org.id
}

output "tofu_github_workspace_id" {
  description = "Workspace id for the tofu-github consumer"
  value       = terrakube_workspace_cli.tofu_github.id
}
