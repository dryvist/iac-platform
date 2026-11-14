# Hourly PR status post.
#
# Declared apart from templates.tf to keep that file under the size limit,
# same as templates-pr-reconcile.tf. Its play runs on localhost only: no host
# pattern, the play names localhost itself, so it passes `-i localhost,` the
# way the OpenBao templates do.
#
# One template does the whole job: the PR census is a step inside
# playbooks/pr-status-post.yml, and the chat status posted is built from
# those census numbers. There is deliberately no separate census template.
#
# The census owners and chat channel reach the playbook through the apps
# environment, never this declaration. The playbook runs from the project's
# own deployed checkout, the one its inventory already points at.
resource "semaphoreui_project_template" "pr_status_post" {
  project_id     = semaphoreui_project.each["apps"].id
  repository_id  = semaphoreui_project_inventory.homelab_tofu["apps"].file.repository_id
  inventory_id   = semaphoreui_project_inventory.homelab_tofu["apps"].id
  environment_id = semaphoreui_project_environment.homelab["apps"].id

  # Deployed ref only: this one is scheduled, and nothing scheduled runs an
  # unreleased ref.
  view_id = semaphoreui_project_view.each["apps/deployed"].id

  name        = "pr-status-post"
  description = "Gathers the open PR census and posts the chat status built from it; owners and channels come from the environment."

  app      = "bash"
  playbook = "semaphore-run-ansible.sh"
  arguments = [
    "./scripts/run-ansible.sh", "playbooks/pr-status-post.yml",
    "-i", "localhost,",
    "--limit", "localhost", "--diff",
  ]

  # Success alerts would fire every hour; failures still alert.
  allow_override_args_in_task = false
  suppress_success_alerts     = true
}
