locals {
  scheduled_templates = {
    for k, t in local.ansible_templates : k => t if try(t.schedule_enabled, false)
  }

  schedule_crons = {
    apps-verify-grafana-dashboards = "17 6 * * *"
    splunk-validate                = "37 6 * * *"
    splunk-weekly-update           = "17 22 * * 4"
  }
}

resource "terraform_data" "schedule_guard" {
  lifecycle {
    precondition {
      condition     = alltrue([for k, _ in local.schedule_crons : contains(keys(local.scheduled_templates), k)])
      error_message = "Every scheduled template must explicitly opt into scheduling."
    }
    precondition {
      condition     = alltrue([for k, _ in local.scheduled_templates : contains(keys(local.schedule_crons), k)])
      error_message = "Every template that explicitly opts into scheduling needs a cron."
    }
    precondition {
      condition = alltrue([
        for k, t in local.scheduled_templates : !t.mutating || k == "splunk-weekly-update"
      ])
      error_message = "Only splunk-weekly-update may be both mutating and scheduled."
    }
    # Nothing unattended may run an unreleased ref. This asserts on the
    # `deployed` flag carried through from repositories.tf rather than on the
    # shape of the key, because a naming convention is not a control.
    precondition {
      condition = alltrue([
        for k, _ in local.schedule_crons :
        try(local.ansible_template_refs[k].deployed, false)
      ])
      error_message = "A cron is declared for a template that is not built from its repository's deployed branch. Scheduled runs are for the deployed ref only."
    }
  }
}

resource "semaphoreui_project_schedule" "scheduled" {
  for_each = local.schedule_crons

  project_id  = semaphoreui_project.homelab.id
  template_id = semaphoreui_project_template.ansible[each.key].id
  name        = each.key
  cron_format = each.value
  enabled     = true
}

moved {
  from = semaphoreui_project_schedule.non_mutating
  to   = semaphoreui_project_schedule.scheduled
}

# The Nautobot parity report, scheduled separately because it is not one of the
# wrapped Ansible templates. Safe to run unattended for a specific, checked
# reason: the script writes nothing and returns non-zero only on an API or IO
# error, so drift produces a report rather than a red run.
resource "semaphoreui_project_schedule" "nautobot_drift" {
  project_id  = semaphoreui_project.homelab.id
  template_id = semaphoreui_project_template.nautobot_drift.id
  name        = "nautobot-drift-report"
  cron_format = "47 6 * * *"
  enabled     = true
}

# Every 12h, off the :00/:30 mark. Declared apart from
# schedule_crons/scheduled_templates, same as nautobot_drift's schedule above.
resource "semaphoreui_project_schedule" "openbao_rotate_scheduled" {
  project_id  = semaphoreui_project.homelab.id
  template_id = semaphoreui_project_template.openbao_rotate_scheduled.id
  name        = "openbao-rotate-approles-scheduled"
  cron_format = "13 3,15 * * *"
  enabled     = true
}
