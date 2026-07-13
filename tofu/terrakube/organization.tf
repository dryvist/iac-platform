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
  name            = var.admin_group
  organization_id = terrakube_organization.org.id
  role            = "admin"
}

# Deliberately NO team token / CI credentials: consumers use Terrakube's
# native CLI-driven flow (tofu login once per machine; interactive apply
# confirm; UI approval templates). CI plan/apply choreography — and the
# team token it would need — gets added only if a real recurring need
# appears (simplicity directive, 2026-07-03).
