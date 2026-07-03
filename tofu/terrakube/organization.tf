# Organization + access model.
#
# The admin team's NAME equals the dex group claim ("org:team-slug" from the
# github connector) — that string match is how Terrakube maps a logged-in
# user's groups onto team permissions. TERRAKUBE_ADMIN_GROUP (compose env)
# additionally grants instance-level admin to the same group.
resource "terrakube_organization" "org" {
  name           = var.organization_name
  description    = "Organization governance + homelab IaC, centrally planned and applied"
  execution_mode = "remote"
}

resource "terrakube_team" "admins" {
  name            = var.admin_group
  organization_id = terrakube_organization.org.id
  role            = "admin"
}

# CI token: what GitHub Actions runners present as
# TF_TOKEN_terrakube__api_pve_jacobpevans_com. MVP scoping note: this token
# carries the admin team's privileges; tightening CI to a plan-scoped team is
# phase-2 hardening. Master copy of the value goes to the GitHub org secret
# TERRAKUBE_TEAM_TOKEN (+ a recovery copy in Doppler ai-ci-automation/prd).
resource "terrakube_team_token" "ci" {
  description = "GitHub Actions runners: remote plan/apply via the TFC-compatible backend"
  team_name   = terrakube_team.admins.name
  days        = var.ci_token_days
  hours       = 0
  minutes     = 0
}
