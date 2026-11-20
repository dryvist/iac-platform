# Hourly status posts rendered by playbooks/status-post.yml in the apps
# repository, one template and one schedule per post. A Semaphore schedule
# carries no task parameters, so the post is chosen by each template's own
# `-e status_post=<key>` argument; the map below is the one place a post is
# added. The metrics endpoint and chat channel reach the playbook through the
# apps environment, never this declaration.

locals {
  # Odd minutes, off the quarter-hour marks; the lane post owns :53.
  status_posts = {
    tracker = "37 * * * *"
    gpu     = "7,37 * * * *"
  }
}

resource "semaphoreui_project_template" "status_post" {
  for_each = local.status_posts

  project_id     = semaphoreui_project.each["apps"].id
  repository_id  = semaphoreui_project_inventory.homelab_tofu["apps"].file.repository_id
  inventory_id   = semaphoreui_project_inventory.homelab_tofu["apps"].id
  environment_id = semaphoreui_project_environment.homelab["apps"].id

  # Deployed ref only: this one is scheduled, and nothing scheduled runs an
  # unreleased ref.
  view_id = semaphoreui_project_view.each["apps/deployed"].id

  name        = "status-post-${each.key}"
  description = "Renders and posts the ${each.key} status from the metrics store; the endpoint and channel come from the environment."

  app      = "bash"
  playbook = "semaphore-run-ansible.sh"
  arguments = [
    "./scripts/run-ansible.sh", "playbooks/status-post.yml",
    "-i", "localhost,",
    "--limit", "localhost",
    "-e", "status_post=${each.key}",
  ]

  # Success alerts would fire every hour; failures still alert.
  allow_override_args_in_task = false
  suppress_success_alerts     = true
}

# Gated by recurring_jobs_enabled like pr_status_post: left false, applying
# this creates the schedules disabled.
resource "semaphoreui_project_schedule" "status_post" {
  for_each = local.status_posts

  project_id  = semaphoreui_project_template.status_post[each.key].project_id
  template_id = semaphoreui_project_template.status_post[each.key].id
  name        = "status-post-${each.key}"
  cron_format = each.value
  enabled     = var.recurring_jobs_enabled
}
