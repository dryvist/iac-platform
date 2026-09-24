# Organization + access model.
#
# The admin team's name equals the OpenBao group claim forwarded by Dex. That
# exact string match is how Terrakube maps an authenticated identity onto team
# permissions. TERRAKUBE_ADMIN_GROUP grants instance-level admin to the same
# group.
resource "terrakube_organization" "org" {
  name           = var.organization_name
  description    = "Organization governance + homelab IaC, centrally planned and applied"
  execution_mode = "remote"
}

resource "terrakube_team" "admins" {
  # Org-qualified team name (org:team-slug), matching the group shape Dex's
  # GitHub connector forwards and TERRAKUBE_ADMIN_GROUP in the compose env.
  # The org prefix lives here (not in var.admin_group's default) because tofu
  # variable defaults cannot interpolate other variables.
  name            = "${var.organization_name}:${var.admin_group}"
  organization_id = terrakube_organization.org.id

  # "role" is not available on the pinned provider release (see providers.tf) —
  # grant every manage_* permission explicitly instead, which is what "admin"
  # expands to.
  manage_state      = true
  manage_workspace  = true
  manage_module     = true
  manage_provider   = true
  manage_vcs        = true
  manage_template   = true
  manage_job        = true
  manage_collection = true
}

# Deliberately NO team token / CI credentials: consumers use Terrakube's
# native CLI-driven flow (tofu login once per machine; interactive apply
# confirm; approval templates declared in templates.tf). CI plan/apply
# choreography — and the team token it would need — gets added only if a
# real recurring need appears (simplicity directive, 2026-07-03).

import {
  to = terrakube_team.admins
  id = "${terrakube_organization.org.id},b09ff17c-3098-4484-b6a8-3d0ed093be0d"
}

# A team with zero organization-wide permissions; its only rights are the
# workspace_access grant below.
resource "terrakube_team" "desired_state_apply" {
  name            = "${var.organization_name}:desired-state-apply"
  organization_id = terrakube_organization.org.id
}

# Grants that team job create/approve on tofu-proxmox only.
resource "terrakube_workspace_access" "desired_state_apply" {
  organization_id = terrakube_organization.org.id
  workspace_id    = terrakube_workspace_cli.tofu_proxmox.id
  name            = terrakube_team.desired_state_apply.name
  manage_job      = true
}

# Trusts a GitHub Actions OIDC token; its name is the string match to the
# team above (same convention as the admin team's name and the Dex claim).
resource "terrakube_federated_credential" "desired_state_github_actions" {
  name       = terrakube_team.desired_state_apply.name
  issuer_url = "https://token.actions.githubusercontent.com"
  audience   = "terrakube"
}

resource "terrakube_federated_credential_claim" "desired_state_repository" {
  federated_credential_id = terrakube_federated_credential.desired_state_github_actions.id
  claim_key               = "repository"
  claim_value             = var.desired_state_repo
}

resource "terrakube_federated_credential_claim" "desired_state_ref" {
  federated_credential_id = terrakube_federated_credential.desired_state_github_actions.id
  claim_key               = "ref"
  claim_value             = var.desired_state_ref
}
