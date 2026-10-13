# Cribl pack manifest publisher: mirrors the latest release of every cc-* pack
# repo into object storage and publishes the manifest the cribl_packs role
# installs from.
#
# Declared apart from ansible_templates because its plays run on localhost only.
# The catalog appends `,localhost` to a host group and the wrapper fails a run
# whose recap shows only localhost under such a limit; `--limit localhost` is the
# shape for a controller-only playbook (see templates-nautobot.tf).
#
# Develop ref only: the deployed apps ref predates the two-org sync, and nothing
# unreleased is ever scheduled. A deployed-ref twin and a schedule follow once
# the deployed ref carries the same playbook.
resource "semaphoreui_project_template" "apps_sync_cribl_packs_develop" {
  project_id     = semaphoreui_project.each["apps"].id
  repository_id  = semaphoreui_project_repository.ansible["apps/ansible-proxmox-apps@develop"].id
  inventory_id   = semaphoreui_project_inventory.homelab_tofu["apps"].id
  environment_id = semaphoreui_project_environment.homelab["apps"].id
  view_id        = semaphoreui_project_view.each["apps/develop"].id

  name        = "apps-sync-cribl-packs @ develop"
  description = "Mirror the latest cc-* Cribl pack releases into object storage and publish the manifest. Runs the develop ref — unreleased, on demand only, never scheduled."

  app      = "bash"
  playbook = "semaphore-run-ansible.sh"
  arguments = [
    "./scripts/run-ansible.sh", "playbooks/sync-cribl-packs.yml",
    "--limit", "localhost", "--diff",
  ]

  allow_override_args_in_task = false
  suppress_success_alerts     = false
}

# The template was first declared through the catalog; keep its Semaphore id.
moved {
  from = semaphoreui_project_template.ansible["apps-sync-cribl-packs @ develop"]
  to   = semaphoreui_project_template.apps_sync_cribl_packs_develop
}
