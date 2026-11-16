# One project per Ansible run lane: `pve` (ansible-proxmox), `apps`
# (ansible-proxmox-apps), `secrets` (the OpenBao-tagged apps templates plus the
# standalone ansible-secrets-management rotate/seed templates, kept apart so
# they only queue behind each other), `observability` (ansible-splunk) and `ai`
# (ansible-proxmox-ai). A catalog entry lands in its repository's project
# unless it names `project` itself (templates-catalog.tf).
#
# Two concurrency limits, deliberately different:
#
#   * per project, local.project_max_parallel_tasks (1 unless named) — each
#     template has its own checkout and Semaphore runs one task per template
#     at a time, so a project's cap only bounds how many of its templates run
#     at once. `ai` stays at 1: its GPU templates (model campaign, serving,
#     profile, model-store seed) must never overlap each other;
#   * server-wide, var.max_parallel_tasks — the shared memory budget of the
#     runner (compose/docker-compose.yml &max_parallel_tasks, held equal by
#     tests/max_parallel_tasks_contract.tftest.hcl). Cross-project overlap on
#     one host is accepted: apt/dpkg locks are waited on, not raced.
#
# Declarative-drift audit (semaphoreui_project): the provider exposes exactly
# five settable attributes — name, alert, alert_chat, max_parallel_tasks, and
# (implicitly) nothing else; `id` and `created` are computed. All four settable
# ones are declared below, so none of them can drift silently.
locals {
  semaphore_project_names = toset(["pve", "apps", "secrets", "observability", "ai"])

  # Where a catalog entry lands when it does not name `project` itself.
  repository_projects = {
    ansible-proxmox      = "pve"
    ansible-proxmox-apps = "apps"
    ansible-splunk       = "observability"
    ansible-proxmox-ai   = "ai"
  }

  project_max_parallel_tasks = merge(
    { for p in local.semaphore_project_names : p => 1 },
    {
      ai   = 1
      apps = 2
    },
  )
}

resource "semaphoreui_project" "each" {
  for_each = local.semaphore_project_names

  name = "${var.project_name}-${each.value}"

  # Alerting stays off here. Run outcomes reach Splunk through the Ansible
  # converge-telemetry callback and the container log pipeline, not through
  # Semaphore's own notifier — which is global, config-file-only, and cannot be
  # declared per project. alert_chat is Telegram-specific and unused.
  alert      = false
  alert_chat = ""

  max_parallel_tasks = local.project_max_parallel_tasks[each.value]

  lifecycle {
    precondition {
      condition     = local.project_max_parallel_tasks[each.value] <= var.max_parallel_tasks
      error_message = "A project's own cap cannot exceed the server-wide max_parallel_tasks budget."
    }
  }
}

# The original single project becomes `apps`, so it keeps its id and the apps
# templates move in place instead of being recreated.
moved {
  from = semaphoreui_project.homelab
  to   = semaphoreui_project.each["apps"]
}

# Repositories and inventories both REQUIRE an ssh_key_id even when no
# credential is needed. Every repository here is public and cloned over HTTPS,
# and hosts are reached with an ephemeral OpenBao-signed certificate minted per
# run by run-ansible.sh — not with a key stored in Semaphore. So the correct
# key is the special None key rather than a real secret this repo would then
# have to hold.
#
# Declarative-drift audit (semaphoreui_project_key): the settable attributes are
# name, project_id, and exactly one of none / ssh / login_password. `none` is
# chosen and the other two are deliberately absent — setting any of them would
# mean a credential lives in Semaphore, which is what the certificate path
# exists to avoid.
resource "semaphoreui_project_key" "none" {
  for_each = local.semaphore_project_names

  project_id = semaphoreui_project.each[each.value].id
  name       = "none"
  none       = {}
}

moved {
  from = semaphoreui_project_key.none
  to   = semaphoreui_project_key.none["apps"]
}
