# One homelab-tofu inventory per project, all pointing at that project's own
# ansible-proxmox-apps checkout — see repositories.tf for why every project
# has one. inventory/hosts.yml deliberately contains no hosts: every host is
# added by load_tofu.yml, which each playbook imports as its first play. So
# this is a pointer to the loader, not a second copy of the published
# ansible_inventory artifact, and every project needs its own pointer for the
# same reason it needs its own checkout.
#
# The parallel Nautobot-sourced inventory (and the drift report that runs
# against it) stays singular, in the "apps" project only — it is one
# read-only comparison job, not a per-project concern, and duplicating it
# five ways would just be five copies of the same report.
#
# Declarative-drift audit (semaphoreui_project_inventory): the settable
# attributes are name, project_id, ssh_key_id, and exactly one inventory-type
# block of file / static / static_yaml / terraform_workspace / tofu_workspace.
# `file` is chosen for both; the other four are deliberately absent. Within
# `file`, path and repository_id are declared and become_key_id is deliberately
# unset — privilege escalation uses the certificate path, not a stored password
# key.
resource "semaphoreui_project_inventory" "homelab_tofu" {
  for_each = local.semaphore_project_names

  project_id = semaphoreui_project.each[each.value].id
  name       = "homelab-tofu"
  ssh_key_id = semaphoreui_project_key.each[each.value].id

  file = {
    path          = "inventory/hosts.yml"
    repository_id = semaphoreui_project_repository.each["${each.value}/ansible-proxmox-apps"].id
  }
}

# inventory/nautobot.yml is the existing opt-in GraphQL plugin config whose
# group mapping deliberately mirrors load_tofu's, so a future cutover is a
# change of which inventory a template names rather than a rewrite. It
# resolves through NAUTOBOT_URL / NAUTOBOT_TOKEN, which the drift report's
# wrapper script exports from the store at run time.
#
# Nothing references this inventory yet — cutting a converge over to it is a
# separate, deliberate decision. It exists so the drift report can exercise
# the same path a cutover would use.
resource "semaphoreui_project_inventory" "homelab_nautobot" {
  project_id = semaphoreui_project.each["apps"].id
  name       = "homelab-nautobot"
  ssh_key_id = semaphoreui_project_key.each["apps"].id

  file = {
    path          = "inventory/nautobot.yml"
    repository_id = semaphoreui_project_repository.each["apps/ansible-proxmox-apps"].id
  }
}
