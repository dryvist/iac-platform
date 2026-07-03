# One CLI-driven workspace per consuming repo. CLI-driven = the repo's own
# `tofu` (locally or in CI) talks to Terrakube via its cloud block; runs
# execute remotely on the executor; state lives in Terrakube (RustFS bucket).
# VCS-driven workspaces are deliberately not used: Terrakube is internal-only
# (no inbound webhooks) — GitHub Actions on self-hosted runners trigger runs.

# First consumer: dryvist/tofu-github (org governance as code).
resource "terrakube_workspace_cli" "tofu_github" {
  organization_id = terrakube_organization.org.id
  name            = "tofu-github"
  description     = "GitHub org governance as code (rulesets, labels, repo settings)"
  execution_mode  = "remote"
  iac_type        = "tofu"
  iac_version     = var.tofu_version
}

# The org-admin GitHub token the github provider reads at plan/apply time.
# Lives ONLY here (encrypted at rest in Terrakube; injected into executor
# runs) — never on a dev machine, never in CI config.
resource "terrakube_workspace_variable" "tofu_github_token" {
  organization_id = terrakube_organization.org.id
  workspace_id    = terrakube_workspace_cli.tofu_github.id
  key             = "GITHUB_TOKEN"
  value           = var.github_org_admin_token
  description     = "GitHub org-admin token for the integrations/github provider"
  category        = "ENV"
  sensitive       = true
  hcl             = false
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
