# One template per (project, playbook) Semaphore may run.
#
# Every Ansible template is a `bash` template invoking the recap wrapper, never
# `ansible-playbook` and never run-ansible.sh directly:
#
#   semaphore-run-ansible.sh ./scripts/run-ansible.sh <playbook> --limit <hosts>,localhost --diff
#
# The wrapper is baked into the image at /usr/local/bin by
# compose/semaphore/Dockerfile, so it is named without a path: `bash <name>`
# resolves a slash-free script through PATH, while a path would be interpreted
# relative to the checked-out Ansible repository, which does not carry it.
#
# Three constraints, each of which has already cost this estate a bad run:
#
#   * `--limit` must include `localhost`. The tofu inventory is loaded by a play
#     inside the playbook, so a limit that excludes localhost skips that play
#     and the whole run no-ops at exit 0.
#   * `--diff`, never `--check`. A dry run is not a converge and must not be
#     able to masquerade as one.
#   * the wrapper applies the PLAY RECAP as the verdict instead of trusting the
#     wrapped exit code, because run-ansible.sh can exit 0 on a run interrupted
#     mid-play. Calling run-ansible.sh bare loses that.
#
# Declarative-drift audit (semaphoreui_project_template): settable attributes are
# name, project_id, repository_id, inventory_id, environment_id, app, playbook,
# arguments, description, git_branch, view_id, allow_override_args_in_task,
# suppress_success_alerts, and the build / deploy / survey_vars / task_params /
# vaults blocks. Declared below: the identity and wiring fields, app, playbook,
# arguments, description, allow_override_args_in_task and
# suppress_success_alerts and view_id. Deliberately absent: git_branch (the
# repository's own branch governs), build and deploy (artifact templates,
# unused), survey_vars (a prompt is a manual input, which is the thing this
# root exists to remove), task_params and vaults.
#
# `project_id` is ForceNew on this resource: moving a template from one
# project to another (this file's split) is a destroy-and-recreate, not an
# in-place move — every template here gets a NEW numeric id on apply. Nothing
# that dispatches by numeric id (the reconcile-token API path,
# ~/git/AGENTS.local.d/semaphore-dispatch.md) survives this apply unchanged;
# the id map needs republishing there after.
#
# The catalog itself (local.ansible_templates) lives in templates-catalog*.tf,
# and now carries a `project` field per entry — see repositories.tf for what
# that field drives.

# A limit that already names localhost would produce `localhost,localhost`, and
# an empty one would drop the real hosts entirely — the exact footgun the
# wrapper's third rule exists to catch. Fail at plan time instead.
resource "terraform_data" "limit_guard" {
  lifecycle {
    precondition {
      condition = alltrue([
        for k, t in local.ansible_templates :
        length(trimspace(t.limit)) > 0 && !strcontains(t.limit, "localhost")
      ])
      error_message = "Every ansible_templates entry needs a non-empty limit that does not itself name localhost; the argument list appends it."
    }
    precondition {
      condition = alltrue([
        for k, t in local.ansible_templates : contains(local.semaphore_project_names, t.project)
      ])
      error_message = "Every ansible_templates entry needs a project naming one of the declared semaphore_project_names (project.tf)."
    }
  }
}

resource "semaphoreui_project_template" "ansible" {
  for_each = local.ansible_templates

  project_id     = semaphoreui_project.each[each.value.project].id
  repository_id  = semaphoreui_project_repository.each["${each.value.project}/${each.value.repository}"].id
  inventory_id   = semaphoreui_project_inventory.homelab_tofu[each.value.project].id
  environment_id = semaphoreui_project_environment.each[each.value.project].id

  name        = each.key
  description = each.value.description

  app      = "bash"
  playbook = "semaphore-run-ansible.sh"
  arguments = concat(
    ["./scripts/run-ansible.sh", each.value.playbook],
    try(each.value.tags, null) != null ? ["--tags", each.value.tags] : [],
    ["--limit", "${each.value.limit},localhost", "--diff"],
    try(each.value.extra_args, []),
  )

  # The argument list is the contract. Letting a task edit it at launch would
  # allow --check, a dropped localhost, or a different playbook entirely —
  # every guard above, bypassable from the UI.
  allow_override_args_in_task = false

  # Success is not silent: outcomes reach Splunk through the converge-telemetry
  # callback and the run output through the container log pipeline.
  suppress_success_alerts = false
}

# The Nautobot parity report: a localhost-only playbook that resolves the
# published inventory artifact, reads the read-only Nautobot credential from
# the store for the duration of the play, and runs the comparison script. By
# that script's own contract it exits non-zero only on an API error, never on
# drift, which is what makes it safe to schedule — see schedules.tf. It runs
# through the same wrapper as every other template, so the run environment
# carries nothing for it. Declared apart from ansible_templates because it has
# no host pattern: the play names localhost itself. Lives in the "apps"
# project only — see inventories.tf.
resource "semaphoreui_project_template" "nautobot_drift" {
  project_id     = semaphoreui_project.each["apps"].id
  repository_id  = semaphoreui_project_repository.each["apps/ansible-proxmox-apps"].id
  inventory_id   = semaphoreui_project_inventory.homelab_nautobot.id
  environment_id = semaphoreui_project_environment.each["apps"].id

  name        = "nautobot-drift-report"
  description = "Read-only report comparing Nautobot against the published inventory."

  app      = "bash"
  playbook = "semaphore-run-ansible.sh"
  arguments = [
    "./scripts/run-ansible.sh", "playbooks/nautobot-drift.yml",
    "--limit", "localhost",
  ]

  allow_override_args_in_task = false
  suppress_success_alerts     = false
}

# Every 12h: rotate openbao_secrets domain AppRole secret_ids. Declared
# apart from ansible_templates: no host pattern, the play names localhost
# itself.
# Auth: the scheduled AppRole pair from the platform env document the
# wrapper exports.
resource "semaphoreui_project_template" "openbao_rotate_scheduled" {
  project_id     = semaphoreui_project.homelab.id
  repository_id  = semaphoreui_project_repository.ansible["ansible-proxmox-apps"].id
  inventory_id   = semaphoreui_project_inventory.homelab_tofu.id
  environment_id = semaphoreui_project_environment.homelab.id

  # Deployed ref only: this one is scheduled, and nothing scheduled runs an
  # unreleased ref.
  view_id = semaphoreui_project_view.deployed.id

  name        = "openbao-rotate-approles-scheduled"
  description = "Scheduled rotation of openbao_secrets domain AppRole secret_ids."

  app      = "bash"
  playbook = "semaphore-run-ansible.sh"
  arguments = [
    "./scripts/run-ansible.sh", "playbooks/openbao-rotate-approles.yml",
    "--limit", "localhost", "--diff",
  ]

  allow_override_args_in_task = false
  suppress_success_alerts     = false
}

# One-shot seed of host secret-zero identities into the env document.
# Manual only: no schedule reaches it. Same auth as the scheduled rotation.
resource "semaphoreui_project_template" "openbao_seed_host_secret_zero" {
  project_id     = semaphoreui_project.homelab.id
  repository_id  = semaphoreui_project_repository.ansible["ansible-proxmox-apps@develop"].id
  inventory_id   = semaphoreui_project_inventory.homelab_tofu.id
  environment_id = semaphoreui_project_environment.homelab.id
  view_id        = semaphoreui_project_view.preview["develop"].id

  name        = "openbao-seed-host-secret-zero @ develop"
  description = "Seeds host secret-zero AppRole pairs into the env document; skips any already present. Runs the develop ref, on demand only."

  app      = "bash"
  playbook = "semaphore-run-ansible.sh"
  arguments = [
    "./scripts/run-ansible.sh", "playbooks/openbao-seed-host-secret-zero.yml",
    "--limit", "localhost", "--diff",
  ]

  allow_override_args_in_task = false
  suppress_success_alerts     = false
}
