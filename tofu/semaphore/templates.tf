# One template per playbook Semaphore may run.
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
# repository's own branch governs — an override here would silently run a
# different ref than the one declared in repositories.tf; running a second ref
# is expressed instead by a second repository entry, which puts the ref in the
# repository name, the template name and the view), build and deploy (artifact
# templates, unused), survey_vars (a prompt is a manual input, which is the
# thing this root exists to remove), task_params and vaults.

# The catalog itself (local.ansible_templates) lives in templates-catalog.tf.

# Cross the playbooks with the refs their repository may be run from.
#
# The deployed ref keeps the bare template key, so its resource address, its
# name in the UI and every schedule that reaches it are all unchanged — this
# adds templates, it does not renumber the existing ones. A preview ref gets
# `<template> @ <branch>`, which is what the run history will show.
#
# `deployed` rides along because schedules.tf must be able to assert that
# nothing unattended reaches a preview ref, and asserting on a substring of the
# key would be a naming convention pretending to be a control.
#
# A template marked `deployed_only` gets no preview variant at all: removing
# the flag is the only way to bring one back, so it cannot reappear by adding a
# preview branch to the repository.
locals {
  ansible_template_refs = {
    for pair in flatten([
      for tname, t in local.ansible_templates : [
        for rkey, r in local.repository_refs : {
          key = r.deployed ? tname : "${tname} @ ${r.branch}"
          value = merge(t, {
            repository_key = rkey
            branch         = r.branch
            deployed       = r.deployed
            template       = tname
          })
        } if r.repo == t.repository && (r.deployed || !try(t.deployed_only, false))
      ]
    ]) : pair.key => pair.value
  }
}

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
  }
}

resource "semaphoreui_project_template" "ansible" {
  for_each = local.ansible_template_refs

  project_id     = semaphoreui_project.homelab.id
  repository_id  = semaphoreui_project_repository.ansible[each.value.repository_key].id
  inventory_id   = semaphoreui_project_inventory.homelab_tofu.id
  environment_id = semaphoreui_project_environment.homelab.id

  # Deployed templates sit on the first tab; a preview ref gets its own, so
  # picking one is a deliberate act rather than a misread of a list.
  view_id = each.value.deployed ? semaphoreui_project_view.deployed.id : semaphoreui_project_view.preview[each.value.branch].id

  name = each.key
  description = each.value.deployed ? each.value.description : join(" ", [
    each.value.description,
    "Runs the ${each.value.branch} ref — unreleased, on demand only, never scheduled.",
  ])

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
# no host pattern: the play names localhost itself.
#
# It is bound to the Nautobot inventory rather than the tofu one so that the
# scheduled job exercises the same resolution path a future cutover would use.
resource "semaphoreui_project_template" "nautobot_drift" {
  project_id     = semaphoreui_project.homelab.id
  repository_id  = semaphoreui_project_repository.ansible["ansible-proxmox-apps"].id
  inventory_id   = semaphoreui_project_inventory.homelab_nautobot.id
  environment_id = semaphoreui_project_environment.homelab.id

  # Deployed ref only: this one is scheduled, and nothing scheduled runs an
  # unreleased ref.
  view_id = semaphoreui_project_view.deployed.id

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
