# The pr-reconcile dispatcher: a localhost-only template on the apps tofu
# inventory, running from the deployed view only, with its schedule declared
# alongside it in schedules.tf — both halves are pinned here.

run "pr_reconcile_dispatch_template_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "arguments\\s*=\\s*\\[[\\s\\S]*?\\\"playbooks/pr-reconcile-dispatch\\.yml\\\"",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"pr_reconcile_dispatch\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-pr-reconcile.tf")
      )[0]
    ))
    error_message = "pr_reconcile_dispatch must pass playbooks/pr-reconcile-dispatch.yml to the runner."
  }

  assert {
    condition = can(regex(
      "view_id\\s*=\\s*semaphoreui_project_view[.]each\\[\\\"apps/deployed\\\"\\][.]id",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"pr_reconcile_dispatch\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-pr-reconcile.tf")
      )[0]
    ))
    error_message = "pr_reconcile_dispatch must use the deployed-ref view."
  }

  assert {
    condition = can(regex(
      "allow_override_args_in_task\\s*=\\s*false",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"pr_reconcile_dispatch\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-pr-reconcile.tf")
      )[0]
    ))
    error_message = "pr_reconcile_dispatch must disallow task argument overrides."
  }

  assert {
    condition = can(regex(
      "suppress_success_alerts\\s*=\\s*true",
      regex(
        "resource \\\"semaphoreui_project_template\\\" \\\"pr_reconcile_dispatch\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../templates-pr-reconcile.tf")
      )[0]
    ))
    error_message = "pr_reconcile_dispatch must suppress success alerts; failures still alert."
  }
}

run "pr_reconcile_dispatch_schedule_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "cron_format\\s*=\\s*\\\"2-57/5 \\* \\* \\* \\*\\\"",
      regex(
        "resource \\\"semaphoreui_project_schedule\\\" \\\"pr_reconcile_dispatch\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../schedules.tf")
      )[0]
    ))
    error_message = "pr_reconcile_dispatch must run every 5 minutes on the 2-57/5 offset."
  }

  assert {
    condition = can(regex(
      "enabled\\s*=\\s*true",
      regex(
        "resource \\\"semaphoreui_project_schedule\\\" \\\"pr_reconcile_dispatch\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../schedules.tf")
      )[0]
    ))
    error_message = "pr_reconcile_dispatch's schedule must be enabled."
  }

  assert {
    condition = can(regex(
      "template_id\\s*=\\s*semaphoreui_project_template[.]pr_reconcile_dispatch[.]id",
      regex(
        "resource \\\"semaphoreui_project_schedule\\\" \\\"pr_reconcile_dispatch\\\" \\{([^}]*)\\}",
        file("${path.module}/../../../schedules.tf")
      )[0]
    ))
    error_message = "pr_reconcile_dispatch's schedule must bind the dispatcher template."
  }
}

run "pr_reconcile_dispatch_cron_contract_rejects_other_values" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = !can(regex(
      "cron_format\\s*=\\s*\\\"2-57/5 \\* \\* \\* \\*\\\"",
      regex(
        "resource \\\"semaphoreui_project_schedule\\\" \\\"pr_reconcile_dispatch\\\" \\{([^}]*)\\}",
        replace(
          file("${path.module}/../../../schedules.tf"),
          "2-57/5 * * * *",
          "0 * * * *",
        )
      )[0]
    ))
    error_message = "The cron assertion must reject a schedule that is not the 2-57/5 offset."
  }
}
