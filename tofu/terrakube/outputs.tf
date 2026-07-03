output "organization_id" {
  description = "Terrakube organization id"
  value       = terrakube_organization.org.id
}

output "tofu_github_workspace_id" {
  description = "Workspace id for the tofu-github consumer"
  value       = terrakube_workspace_cli.tofu_github.id
}

output "ci_team_token" {
  description = "Team token for CI runners (store as GitHub org secret TERRAKUBE_TEAM_TOKEN; recovery copy in Doppler). Read with: tofu output -raw ci_team_token"
  value       = terrakube_team_token.ci.value
  sensitive   = true
}
