# Object-store repair. Use it when the object store is full or refusing reads,
# so ordinary converges cannot resolve the inventory — the published artifact
# is served from the store itself. It runs only the object-store play
# (playbooks/site.yml limited to object_storage_group,localhost) on the
# Nautobot inventory, the invocation the object-store play's banner in
# ansible-proxmox-apps documents. Declared apart from the ansible_templates
# catalog because the shared template resource there pins every entry to the
# tofu inventory (templates.tf); the Nautobot URL and token reach the run
# through the same apps environment every template shares (environments.tf),
# exactly as the Nautobot collection templates use it. Manual only: no
# schedule reaches it.
resource "semaphoreui_project_template" "apps_object_store_repair" {
  project_id     = semaphoreui_project.each["apps"].id
  repository_id  = semaphoreui_project_repository.ansible["apps/ansible-proxmox-apps"].id
  inventory_id   = semaphoreui_project_inventory.homelab_nautobot.id
  environment_id = semaphoreui_project_environment.homelab["apps"].id
  view_id        = semaphoreui_project_view.each["apps/deployed"].id

  name        = "apps-object-store-repair"
  description = "Object-store repair only: the object-store play of playbooks/site.yml on the Nautobot inventory (-i inventory/nautobot.yml), for when the store cannot serve the published inventory."

  app      = "bash"
  playbook = "semaphore-run-ansible.sh"
  arguments = [
    "./scripts/run-ansible.sh", "playbooks/site.yml",
    "--limit", "object_storage_group,localhost",
    "-i", "inventory/nautobot.yml",
    "--diff",
  ]

  allow_override_args_in_task = false
  suppress_success_alerts     = false
}
