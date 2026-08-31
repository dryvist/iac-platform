# Schedules — NON-MUTATING TEMPLATES ONLY.
#
# A scheduled template runs with nobody watching. Everything that converges
# stays on-demand: run-ansible.sh mints a 2h OpenBao-signed certificate per run
# and refuses a stale checkout, and site.yml aborts every later play when one
# play fails for all of its hosts. Those are the right behaviours for a person
# who is present and the wrong ones to discover from a cron entry.
#
# The gate is mechanical rather than editorial: the set below is DERIVED from
# `mutating = false` in templates.tf, so marking a template mutating removes its
# schedule, and adding a schedule for a mutating template is not expressible
# here. A precondition asserts it anyway, because a derivation that is silently
# wrong is worse than no derivation.
#
# Declarative-drift audit (semaphoreui_project_schedule): the settable
# attributes are name, project_id, template_id, cron_format and enabled. All
# five are declared.

locals {
  # Off-peak and off the :00 mark so these never land on the same minute as
  # every other cron in the estate.
  scheduled_templates = {
    for k, t in local.ansible_templates : k => t if !t.mutating
  }

  schedule_crons = {
    apps-verify-grafana-dashboards = "17 6 * * *"
    splunk-validate                = "37 6 * * *"
  }
}

resource "terraform_data" "schedule_guard" {
  lifecycle {
    precondition {
      condition     = alltrue([for k, _ in local.schedule_crons : contains(keys(local.scheduled_templates), k)])
      error_message = "A cron is declared for a template that is not marked mutating = false. Schedules are for non-mutating templates only."
    }
    precondition {
      condition     = alltrue([for k, _ in local.scheduled_templates : contains(keys(local.schedule_crons), k)])
      error_message = "A non-mutating template has no cron. Give it one, or mark it mutating — silence here means a schedule was dropped by accident."
    }
  }
}

resource "semaphoreui_project_schedule" "non_mutating" {
  for_each = local.schedule_crons

  project_id  = semaphoreui_project.homelab.id
  template_id = semaphoreui_project_template.ansible[each.key].id
  name        = each.key
  cron_format = each.value
  enabled     = true
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
