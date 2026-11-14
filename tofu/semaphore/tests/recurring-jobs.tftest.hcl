# The hourly PR status post: one template, one schedule, the census gathered
# inside playbooks/pr-status-post.yml rather than by a separate template.
# Both halves are pinned here the way the pr_reconcile_dispatch contract pins
# its halves, plus the recurring_jobs_enabled gate itself and a final run
# asserting that the gate reaches nothing else — pr_reconcile_dispatch's cron
# and enabled stay literal, and the schedule guard's cron map stays untouched.

run "recurring_jobs_enabled_defaults_false" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "variable \\\"recurring_jobs_enabled\\\" \\{[^{}]*type\\s*=\\s*bool",
      file("${path.module}/../../../variables.tf")
    ))
    error_message = "recurring_jobs_enabled must be a bool."
  }

  assert {
    condition = can(regex(
      "variable \\\"recurring_jobs_enabled\\\" \\{[^{}]*default\\s*=\\s*false",
      file("${path.module}/../../../variables.tf")
    ))
    error_message = "recurring_jobs_enabled must default to false so merging and applying this configuration creates every gated schedule disabled."
  }
}

run "pr_status_post_template_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "name\\s*=\\s*\\\"pr-status-post\\\"",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"pr_status_post\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-pr-census.tf")
      )[0]
    ))
    error_message = "The template must be named pr-status-post."
  }

  assert {
    condition = can(regex(
      "app\\s*=\\s*\\\"bash\\\"[\\s\\S]*?playbook\\s*=\\s*\\\"semaphore-run-ansible\\.sh\\\"",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"pr_status_post\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-pr-census.tf")
      )[0]
    ))
    error_message = "pr_status_post must be a bash template invoking the recap wrapper."
  }

  assert {
    condition = can(regex(
      "arguments\\s*=\\s*\\[\\s*\\\"\\./scripts/run-ansible\\.sh\\\", \\\"playbooks/pr-status-post\\.yml\\\",\\s*\\\"-i\\\", \\\"localhost,\\\",\\s*\\\"--limit\\\", \\\"localhost\\\", \\\"--diff\\\",?\\s*\\]",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"pr_status_post\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-pr-census.tf")
      )[0]
    ))
    error_message = "pr_status_post must pass exactly playbooks/pr-status-post.yml to the runner with -i localhost, --limit localhost --diff and nothing else."
  }

  assert {
    condition = !can(regex(
      "(?i)(token|secret|password|api[_-]?key|ghp_|github_pat_)",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"pr_status_post\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-pr-census.tf")
      )[0]
    ))
    error_message = "pr_status_post's declaration must be secret-free; its inputs reach the playbook through the run environment."
  }

  assert {
    condition = can(regex(
      "view_id\\s*=\\s*semaphoreui_project_view[.]each\\[\\\"apps/deployed\\\"\\][.]id",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"pr_status_post\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-pr-census.tf")
      )[0]
    ))
    error_message = "pr_status_post must use the deployed-ref view."
  }

  assert {
    condition = alltrue([
      can(regex(
        "repository_id\\s*=\\s*semaphoreui_project_inventory[.]homelab_tofu\\[\\\"apps\\\"\\][.]file[.]repository_id",
        regex(
          "resource \\\"semaphoreui_project_template\\\" \\\"pr_status_post\\\" \\{([^}]*)\\}",
          file("${path.module}/../../../templates-pr-census.tf")
        )[0]
      )),
      can(regex(
        "inventory_id\\s*=\\s*semaphoreui_project_inventory[.]homelab_tofu\\[\\\"apps\\\"\\][.]id",
        regex(
          "resource \\\"semaphoreui_project_template\\\" \\\"pr_status_post\\\" \\{([^}]*)\\}",
          file("${path.module}/../../../templates-pr-census.tf")
        )[0]
      )),
      can(regex(
        "environment_id\\s*=\\s*semaphoreui_project_environment[.]homelab\\[\\\"apps\\\"\\][.]id",
        regex(
          "resource \\\"semaphoreui_project_template\\\" \\\"pr_status_post\\\" \\{([^}]*)\\}",
          file("${path.module}/../../../templates-pr-census.tf")
        )[0]
      )),
    ])
    error_message = "pr_status_post must share pr_reconcile_dispatch's wiring: the apps deployed checkout, the apps tofu inventory, the apps environment."
  }

  assert {
    condition = alltrue([
      can(regex(
        "allow_override_args_in_task\\s*=\\s*false",
        regex(
          "resource \\\"semaphoreui_project_template\\\" \\\"pr_status_post\\\" \\{([^}]*)\\}",
          file("${path.module}/../../../templates-pr-census.tf")
        )[0]
      )),
      can(regex(
        "suppress_success_alerts\\s*=\\s*true",
        regex(
          "resource \\\"semaphoreui_project_template\\\" \\\"pr_status_post\\\" \\{([^}]*)\\}",
          file("${path.module}/../../../templates-pr-census.tf")
        )[0]
      )),
    ])
    error_message = "pr_status_post must disallow task argument overrides and suppress success alerts; failures still alert."
  }
}

run "pr_status_post_schedule_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "cron_format\\s*=\\s*\\\"53 \\* \\* \\* \\*\\\"",
      regex(
        "resource \\\"semaphoreui_project_schedule\\\" \\\"pr_status_post\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../schedules.tf")
      )[0]
    ))
    error_message = "pr_status_post must run hourly at minute 53."
  }

  assert {
    condition = tonumber(regex(
      "cron_format\\s*=\\s*\\\"([0-9]+) \\* \\* \\* \\*\\\"",
      regex(
        "resource \\\"semaphoreui_project_schedule\\\" \\\"pr_status_post\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../schedules.tf")
      )[0]
    )[0]) % 2 == 1
    error_message = "The hourly minute must be odd."
  }

  assert {
    condition = !contains([0, 15, 30, 45], tonumber(regex(
      "cron_format\\s*=\\s*\\\"([0-9]+) \\* \\* \\* \\*\\\"",
      regex(
        "resource \\\"semaphoreui_project_schedule\\\" \\\"pr_status_post\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../schedules.tf")
      )[0]
    )[0]))
    error_message = "The hourly minute must sit off the quarter-hour marks."
  }

  assert {
    condition = can(regex(
      "enabled\\s*=\\s*var[.]recurring_jobs_enabled",
      regex(
        "resource \\\"semaphoreui_project_schedule\\\" \\\"pr_status_post\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../schedules.tf")
      )[0]
    ))
    error_message = "pr_status_post's schedule must be enabled by the recurring_jobs_enabled variable, not hardcoded."
  }

  assert {
    condition = alltrue([
      can(regex(
        "project_id\\s*=\\s*semaphoreui_project_template[.]pr_status_post[.]project_id",
        regex(
          "resource \\\"semaphoreui_project_schedule\\\" \\\"pr_status_post\\\" \\{([^}]*)\\}",
          file("${path.module}/../../../schedules.tf")
        )[0]
      )),
      can(regex(
        "template_id\\s*=\\s*semaphoreui_project_template[.]pr_status_post[.]id",
        regex(
          "resource \\\"semaphoreui_project_schedule\\\" \\\"pr_status_post\\\" \\{([^}]*)\\}",
          file("${path.module}/../../../schedules.tf")
        )[0]
      )),
    ])
    error_message = "pr_status_post's schedule must bind the pr_status_post template."
  }
}

run "recurring_jobs_enabled_gates_only_pr_status_post" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = length(regexall(
      "var[.]recurring_jobs_enabled",
      file("${path.module}/../../../schedules.tf")
    )) == 1
    error_message = "recurring_jobs_enabled must appear exactly once in schedules.tf: on the pr_status_post schedule."
  }

  assert {
    condition = !can(regex(
      "var[.]recurring_jobs_enabled",
      regex(
        "resource \\\"semaphoreui_project_schedule\\\" \\\"pr_reconcile_dispatch\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../schedules.tf")
      )[0]
    ))
    error_message = "pr_reconcile_dispatch's schedule must stay literal; the gate reaches only pr_status_post."
  }

  assert {
    condition = alltrue([
      can(regex(
        "cron_format\\s*=\\s*\\\"2-57/5 \\* \\* \\* \\*\\\"",
        regex(
          "resource \\\"semaphoreui_project_schedule\\\" \\\"pr_reconcile_dispatch\\\" \\{([^}]*)\\}",
          file("${path.module}/../../../schedules.tf")
        )[0]
      )),
      can(regex(
        "enabled\\s*=\\s*false",
        regex(
          "resource \\\"semaphoreui_project_schedule\\\" \\\"pr_reconcile_dispatch\\\" \\{([^}]*)\\}",
          file("${path.module}/../../../schedules.tf")
        )[0]
      )),
    ])
    error_message = "pr_reconcile_dispatch's cron and enabled = false must be left untouched by this declaration."
  }

  assert {
    condition = !can(regex(
      "pr-status-post",
      regex(
        "schedule_crons\\s*=\\s*\\{([^}]*)\\}",
        file("${path.module}/../../../schedules.tf")
      )[0]
    ))
    error_message = "The schedule guard's cron map must stay disjoint from the standalone pr_status_post schedule."
  }
}
