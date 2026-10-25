# Nautobot collection templates: sync-in, sync-out, the collection drift check
# and the Homebox feed. Declared apart from templates.tf to keep each file under
# the size limit.

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

# Nautobot -> Homebox feed. The playbook's default is a render-only run that logs
# the feed size and calls nothing in Homebox. The survey value `true` makes it
# read the Homebox API key and post the import. Manual only: no schedule reaches it.
resource "semaphoreui_project_template" "homebox_feed" {
  project_id     = semaphoreui_project.each["apps"].id
  repository_id  = semaphoreui_project_repository.ansible["apps/ansible-proxmox-apps"].id
  inventory_id   = semaphoreui_project_inventory.homelab_nautobot.id
  environment_id = semaphoreui_project_environment.homelab["apps"].id
  view_id        = semaphoreui_project_view.each["apps/deployed"].id

  name        = "homebox-feed"
  description = "Feeds Homebox from Nautobot. Renders only, unless the apply survey value is true."

  app      = "bash"
  playbook = "semaphore-run-ansible.sh"
  arguments = [
    "./scripts/run-ansible.sh", "playbooks/homebox-feed.yml",
    "--limit", "localhost",
  ]

  allow_override_args_in_task = false
  suppress_success_alerts     = false

  # The wrapper turns the bare name=value argument into an Ansible extra var.
  # Left unset, the playbook's own default (false) applies.
  survey_vars = [
    {
      name        = "homebox_feed_apply"
      title       = "Apply to Homebox"
      description = "true posts the import to Homebox. false, or unset, renders the feed and logs its size."
      required    = false
      type        = "enum"
      enum_values = {
        "false" = "false"
        "true"  = "true"
      }
    },
  ]
}
