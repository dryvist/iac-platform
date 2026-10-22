resource "terrakube_workspace_variable" "plan_artifacts" {
  organization_id = terrakube_organization.org.id
  workspace_id    = terrakube_workspace_cli.tofu_runs_on.id
  key             = "TERRAKUBE_PLAN_ARTIFACTS"
  value           = ".terraform/*.zip"
  description     = "Plan-built files to restore before apply"
  category        = "ENV"
  sensitive       = false
  hcl             = false
}
