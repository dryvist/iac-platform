# Two inventories, and the second one is a migration gate rather than a
# duplicate.
#
# Nautobot is the declared system of record for infrastructure inventory. It is
# seeded but nothing reads from it yet, so the tofu-published artifact is still
# what converges run against. Declaring both here — and scheduling the drift
# report in schedules.tf — is what turns "Nautobot is authoritative" from an
# intention into something with evidence behind it, without cutting over
# prematurely.
#
# Neither inventory holds a copy of any host. Both point at a file in the
# checked-out repository, so there is exactly one source of host truth and it is
# resolved at run time, not stored here.
#
# Declarative-drift audit (semaphoreui_project_inventory): the settable
# attributes are name, project_id, ssh_key_id, and exactly one inventory-type
# block of file / static / static_yaml / terraform_workspace / tofu_workspace.
# `file` is chosen for both; the other four are deliberately absent. Within
# `file`, path and repository_id are declared and become_key_id is deliberately
# unset — privilege escalation uses the certificate path, not a stored password
# key.

# The current path. inventory/hosts.yml deliberately contains no hosts: every
# host is added by load_tofu.yml, which each playbook imports as its first play.
# So this is a pointer to the loader, not a second copy of the published
# ansible_inventory artifact.
resource "semaphoreui_project_inventory" "homelab_tofu" {
  project_id = semaphoreui_project.homelab.id
  name       = "homelab-tofu"
  ssh_key_id = semaphoreui_project_key.none.id

  file = {
    path          = "inventory/hosts.yml"
    repository_id = semaphoreui_project_repository.ansible["ansible-proxmox-apps"].id
  }
}

# The parallel Nautobot-sourced inventory. inventory/nautobot.yml is the
# existing opt-in GraphQL plugin config whose group mapping deliberately mirrors
# load_tofu's, so a future cutover is a change of which inventory a template
# names rather than a rewrite. It resolves through NAUTOBOT_URL / NAUTOBOT_TOKEN
# from the environment.
#
# Nothing references this inventory yet — cutting a converge over to it is a
# separate, deliberate decision. It exists so the drift report can exercise the
# same path a cutover would use.
resource "semaphoreui_project_inventory" "homelab_nautobot" {
  project_id = semaphoreui_project.homelab.id
  name       = "homelab-nautobot"
  ssh_key_id = semaphoreui_project_key.none.id

  file = {
    path          = "inventory/nautobot.yml"
    repository_id = semaphoreui_project_repository.ansible["ansible-proxmox-apps"].id
  }
}
