# One base value for Semaphore's task concurrency, shared with
# compose/docker-compose.yml's &max_parallel_tasks anchor
# (SEMAPHORE_MAX_PARALLEL_TASKS on the semaphore service,
# SEMAPHORE_RUNNER_MAX_PARALLEL_TASKS on semaphore-runner) — a single literal
# on each side rather than a runtime-shared source, because compose reads
# compose/.env at deploy time and this root reads TF_VAR_* from the run
# environment, two paths with no common file to point at. Drift between the
# two is caught instead by tests/semaphore-parallel-tasks-contract.sh, which
# parses both files and fails if the values differ.
#
# Ansible's forks actually run in semaphore-runner (not this project's own
# server-side scheduling), sized in compose for K=3 at mem_limit 6144m: an
# "all"-scoped template at forks=12 peaks around 250 MiB parent + 12 x 110
# MiB workers =~ 1.53 GiB, so 3 concurrent tasks fit with room to spare. This
# value and that mem_limit are one budget — raise this only in the same
# change that raises mem_limit, and by the same ratio.
locals {
  max_parallel_tasks = 3
}

# The single project, and the one key every other object references.
#
# Declarative-drift audit (semaphoreui_project): the provider exposes exactly
# five settable attributes — name, alert, alert_chat, max_parallel_tasks, and
# (implicitly) nothing else; `id` and `created` are computed. All four settable
# ones are declared below, so none of them can drift silently.
resource "semaphoreui_project" "homelab" {
  name = var.project_name

  # Alerting stays off here. Run outcomes reach Splunk through the Ansible
  # converge-telemetry callback and the container log pipeline, not through
  # Semaphore's own notifier — which is global, config-file-only, and cannot be
  # declared per project. alert_chat is Telegram-specific and unused.
  alert      = false
  alert_chat = ""

  max_parallel_tasks = local.max_parallel_tasks
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
  project_id = semaphoreui_project.homelab.id
  name       = "none"
  none       = {}
}
