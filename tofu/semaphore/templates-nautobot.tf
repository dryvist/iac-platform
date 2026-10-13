# Nautobot collection templates: sync-in, sync-out and the collection drift
# check. Declared apart from templates.tf to keep each file under the size limit.

resource "semaphoreui_project_template" "nautobot_sync_in" {
  project_id     = semaphoreui_project.each["apps"].id
  repository_id  = semaphoreui_project_repository.ansible["apps/ansible-proxmox-apps"].id
  inventory_id   = semaphoreui_project_inventory.homelab_nautobot.id
  environment_id = semaphoreui_project_environment.homelab["apps"].id
  view_id        = semaphoreui_project_view.each["apps/deployed"].id

  name        = "nautobot-sync-in"
  description = "Runs the Nautobot collection sync-in playbook."

  app      = "bash"
  playbook = "semaphore-run-ansible.sh"
  arguments = [
    "./scripts/run-ansible.sh", "playbooks/nautobot-sync-in.yml",
    "--limit", "localhost",
  ]

  allow_override_args_in_task = false
  suppress_success_alerts     = false
}

resource "semaphoreui_project_template" "nautobot_sync_out" {
  project_id     = semaphoreui_project.each["apps"].id
  repository_id  = semaphoreui_project_repository.ansible["apps/ansible-proxmox-apps"].id
  inventory_id   = semaphoreui_project_inventory.homelab_nautobot.id
  environment_id = semaphoreui_project_environment.homelab["apps"].id
  view_id        = semaphoreui_project_view.each["apps/deployed"].id

  name        = "nautobot-sync-out"
  description = "Runs the Nautobot collection sync-out export playbook."

  app      = "bash"
  playbook = "semaphore-run-ansible.sh"
  arguments = [
    "./scripts/run-ansible.sh", "playbooks/nautobot-sync-out.yml",
    "--limit", "localhost",
  ]

  allow_override_args_in_task = false
  suppress_success_alerts     = false
}

resource "semaphoreui_project_template" "nautobot_drift_collection" {
  project_id     = semaphoreui_project.each["apps"].id
  repository_id  = semaphoreui_project_repository.ansible["apps/ansible-proxmox-apps"].id
  inventory_id   = semaphoreui_project_inventory.homelab_nautobot.id
  environment_id = semaphoreui_project_environment.homelab["apps"].id
  view_id        = semaphoreui_project_view.each["apps/deployed"].id

  name        = "nautobot-drift-collection"
  description = "Runs the collection-based Nautobot drift playbook."

  app      = "bash"
  playbook = "semaphore-run-ansible.sh"
  arguments = [
    "./scripts/run-ansible.sh", "playbooks/nautobot-drift.yml",
    "--limit", "localhost",
  ]

  allow_override_args_in_task = false
  suppress_success_alerts     = false
}
