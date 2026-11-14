# pr-reconcile workflow dispatcher.
#
# Declared apart from templates.tf to keep that file under the size limit,
# same as templates-nautobot.tf and templates-cribl-packs.tf. Its plays run on
# localhost only: no host pattern, the play names localhost itself, so it
# passes `-i localhost,` the way the OpenBao templates do.
#
# The target owner and repository reach the playbook through the apps
# environment, never this declaration. The playbook runs from the project's
# own deployed checkout, the one its inventory already points at.
resource "semaphoreui_project_template" "pr_reconcile_dispatch" {
  project_id     = semaphoreui_project.each["apps"].id
  repository_id  = semaphoreui_project_inventory.homelab_tofu["apps"].file.repository_id
  inventory_id   = semaphoreui_project_inventory.homelab_tofu["apps"].id
  environment_id = semaphoreui_project_environment.homelab["apps"].id

  # Deployed ref only: this one is scheduled, and nothing scheduled runs an
  # unreleased ref.
  view_id = semaphoreui_project_view.each["apps/deployed"].id

  name        = "pr-reconcile-dispatch"
  description = "Dispatches the pr-reconcile GitHub workflow; the target owner and repository come from the environment."

  app      = "bash"
  playbook = "semaphore-run-ansible.sh"
  arguments = [
    "./scripts/run-ansible.sh", "playbooks/pr-reconcile-dispatch.yml",
    "-i", "localhost,",
    "--limit", "localhost",
  ]

  # Success alerts would fire every five minutes; failures still alert.
  allow_override_args_in_task = false
  suppress_success_alerts     = true
}
