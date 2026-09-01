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

  # Serialise runs. Two converges of the same repository at once would race on
  # the shared checkout and on the hosts they both target.
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
resource "semaphoreui_project_key" "none" {
  project_id = semaphoreui_project.homelab.id
  name       = "none"
  none       = {}
}
