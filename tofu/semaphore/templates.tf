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

locals {
  # `limit` is the host pattern WITHOUT localhost; the argument list appends it,
  # so no entry here can forget it.
  #
  # `mutating` drives schedules.tf. It is not a comment — a template marked
  # false is eligible to run unattended, so it is the safety property of this
  # whole file and is asserted on below.
  #
  # `tags` is optional and omitted by almost every entry. Set it only when a
  # playbook must be run for some of its plays rather than in full, and only
  # after confirming each tag is carried by the play itself with a static
  # `roles:` list — `--tags` never reaches inside an untagged `include_role`,
  # and a tag that matches nothing yields a converge that runs cleanly, changes
  # nothing and reports success. A scoped entry still names the ENTRY playbook
  # (the one whose preamble loads the inventory), never an imported fragment
  # of it. A scoped entry is a second template, never an edit to the
  # full-scope one, so narrowing this file can never narrow what an existing
  # caller already gets.
  ansible_templates = {
    apps-site = {
      repository  = "ansible-proxmox-apps"
      playbook    = "playbooks/site.yml"
      limit       = "all"
      mutating    = true
      description = "Full application-layer converge."
    }

    apps-verify-grafana-dashboards = {
      repository  = "ansible-proxmox-apps"
      playbook    = "playbooks/verify-grafana-dashboards.yml"
      limit       = "grafana_group"
      mutating    = false
      description = "Read-only check that provisioned dashboards are loaded."
    }

    apps-validate-pipeline = {
      repository = "ansible-proxmox-apps"
      playbook   = "playbooks/validate-pipeline.yml"
      limit      = "all"
      # Composed of many imported validate-pipeline/* playbooks. Declared so it
      # can be run on demand, but marked mutating because "every imported play
      # is read-only" has not been established for all of them, and an unproven
      # read-only claim is not a basis for running something unattended.
      mutating    = true
      description = "Log-pipeline validation across HAProxy, Cribl Edge and Cribl Stream."
    }

    proxmox-site = {
      repository  = "ansible-proxmox"
      playbook    = "playbooks/site.yml"
      limit       = "all"
      mutating    = true
      description = "Full hypervisor-layer converge."
    }

    proxmox-validate-nas = {
      repository = "ansible-proxmox"
      playbook   = "playbooks/validate-nas.yml"
      limit      = "proxmox"
      # Asserts and reads, but reaches the hosts through ansible.builtin.command
      # whose effect is not verifiable from the module list alone. On demand
      # only until it is.
      mutating    = true
      description = "Validation of the hypervisor SMB shares."
    }

    splunk-site = {
      repository  = "ansible-splunk"
      playbook    = "playbooks/site.yml"
      limit       = "all"
      mutating    = true
      description = "Full Splunk converge."
    }

    splunk-validate = {
      repository  = "ansible-splunk"
      playbook    = "playbooks/validate.yml"
      limit       = "splunk"
      mutating    = false
      description = "Read-only verification of the Splunk deployment."
    }

    ai-site = {
      repository  = "ansible-proxmox-ai"
      playbook    = "playbooks/site.yml"
      limit       = "all"
      mutating    = true
      description = "Full AI/LLM stack converge (Ollama, LiteLLM, Qdrant, Hermes, Langfuse, etc.)."
    }

    # Both scoped AI entries enter through site.yml, never through the
    # llm-serving.yml fragment they narrow to. That file is an import_playbook
    # fragment of site.yml: it carries neither the inventory loader nor the
    # always-tagged secrets pre-fetch, so run on its own it matches no hosts,
    # skips every play and reports success (the recap wrapper caught exactly
    # that). Entering through site.yml keeps both preamble plays, and the tags
    # select the fragment's plays from there.
    ai-llm-serving = {
      repository = "ansible-proxmox-ai"
      playbook   = "playbooks/site.yml"
      limit      = "all"
      # Exactly the four plays llm-serving.yml contains: the two llama.cpp
      # tiers, the spend store and the router. Not the broader `llm` tag —
      # in site.yml it also matches the Ollama and Open WebUI plays.
      tags        = "llama_cpp,llm_redis,llm_router"
      mutating    = true
      description = "GPU inference serving stack converge (llama.cpp, LiteLLM proxy, Redis spend store)."
    }

    ai-llm-router = {
      repository = "ansible-proxmox-ai"
      playbook   = "playbooks/site.yml"
      limit      = "llm_router_group"
      tags       = "llm_router"
      # The sibling above runs all four serving plays, reaching the ROCm tier,
      # the NVIDIA guest and the spend store as well as the router. This entry
      # exists so the router can be converged on its own without owning those
      # three outcomes.
      #
      # Mutating: the play restarts pool members. It does so one at a time
      # (`serial: 1`, `max_fail_percentage: 0`) so the front door stays up,
      # but a rolling restart is still a restart.
      mutating    = true
      description = "LiteLLM router converge only, scoped by tag and limit."
    }
  }
}

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
        } if r.repo == t.repository
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
  )

  # The argument list is the contract. Letting a task edit it at launch would
  # allow --check, a dropped localhost, or a different playbook entirely —
  # every guard above, bypassable from the UI.
  allow_override_args_in_task = false

  # Success is not silent: outcomes reach Splunk through the converge-telemetry
  # callback and the run output through the container log pipeline.
  suppress_success_alerts = false
}

# The Nautobot parity report. Not an Ansible run and not wrapped: it is a
# read-only Python script that queries Nautobot and compares it against the
# published inventory artifact, and by its own contract it exits non-zero only
# on an API error, never on drift. That property is what makes it safe to
# schedule — see schedules.tf.
#
# It runs against the Nautobot inventory rather than the tofu one so that the
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

  app      = "python"
  playbook = "scripts/nautobot_drift.py"
  arguments = [
    "--tofu-inventory", "inventory/tofu_inventory.json",
  ]

  allow_override_args_in_task = false
  suppress_success_alerts     = false
}

# A template named ai-llm-router already exists on the server outside this
# state. Adopt it rather than create a second one under the same name; the
# plan then changes it in place. Remove this block once the import has
# applied — it is a one-time adoption, not part of the declared graph.
import {
  to = semaphoreui_project_template.ansible["ai-llm-router"]
  id = "project/1/template/12"
}
