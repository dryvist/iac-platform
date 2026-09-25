# Five projects, aligned to Ansible repository checkouts rather than to a
# domain label crossing repositories — a project gets exactly one checkout,
# which is the whole point of splitting: a same-checkout race is what a
# project's own max_parallel_tasks=1 prevents, and a race can only happen
# between two runs sharing a working copy. "apps" and "secrets" both check
# out ansible-proxmox-apps (secrets carries only the openbao-tagged,
# privileged templates, kept out of the shared "apps" project so its cap
# bounds ONLY openbao-tagged runs against each other); "pve", "observability"
# and "ai" check out their own domain repository plus ansible-proxmox-apps a
# second time, solely for its inventory/hosts.yml loader (every playbook
# imports it as its first play — see inventories.tf).
#
# Cross-project overlap on the SAME host is accepted: apt/dpkg and similar
# module-level locks are waited on, not raced. What per-project
# max_parallel_tasks=1 exists to prevent is two tasks sharing one CHECKOUT —
# a git operation racing another git operation in the same working directory
# — which is a same-project, not a cross-project, hazard.
#
# The container this all runs in is still one shared memory budget
# (compose/docker-compose.yml SEMAPHORE_MAX_PARALLEL_TASKS +
# mem_limit) regardless of project count — see that file's comment for why
# per-project caps alone are not sufficient.
locals {
  semaphore_project_names = toset(["pve", "apps", "secrets", "observability", "ai"])
}

# Declarative-drift audit (semaphoreui_project): the provider exposes exactly
# five settable attributes — name, alert, alert_chat, max_parallel_tasks, and
# (implicitly) nothing else; `id` and `created` are computed. All four settable
# ones are declared below, so none of them can drift silently.
resource "semaphoreui_project" "each" {
  for_each = local.semaphore_project_names

  name = "${var.project_name}-${each.value}"

  # Alerting stays off here. Run outcomes reach Splunk through the Ansible
  # converge-telemetry callback and the container log pipeline, not through
  # Semaphore's own notifier — which is global, config-file-only, and cannot be
  # declared per project. alert_chat is Telegram-specific and unused.
  alert      = false
  alert_chat = ""

  # Bounds concurrency WITHIN this one project (one checkout, so this is the
  # git-race guard). The server-wide ceiling across every project
  # (SEMAPHORE_MAX_PARALLEL_TASKS, compose/docker-compose.yml) is the actual
  # memory guard — see that file.
  max_parallel_tasks = 1
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
resource "semaphoreui_project_key" "each" {
  for_each = local.semaphore_project_names

  project_id = semaphoreui_project.each[each.value].id
  name       = "none"
  none       = {}
}
