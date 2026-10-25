# Contract: the Nautobot backup entry runs only the role's backup part. The play
# and the role's server and Jobs parts share the `nautobot` tag and task
# arguments only add to a template's own, so dropping the skip tags would turn a
# backup-only run into a full Nautobot converge. Read as raw text, the same way
# max_parallel_tasks_contract.tftest.hcl does, for the reason given in
# fixtures/noop/main.tf.

run "nautobot_backup_template_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "tags\\s*=\\s*\\\"nautobot\\\"",
      regex(
        "apps-nautobot-backup = \\{([^{}]*)\\}",
        file("${path.module}/../../../templates-catalog-apps-nautobot.tf")
      )[0]
    ))
    error_message = "apps-nautobot-backup must keep the play selected with the stored tag nautobot."
  }

  assert {
    condition = can(regex(
      "extra_args\\s*=\\s*\\[\\\"--skip-tags\\\",\\s*\\\"nautobot_server,nautobot_jobs\\\",\\s*\\\"-e\\\",\\s*\\\"nautobot_server_via_collection=true\\\"\\]",
      regex(
        "apps-nautobot-backup = \\{([^{}]*)\\}",
        file("${path.module}/../../../templates-catalog-apps-nautobot.tf")
      )[0]
    ))
    error_message = "apps-nautobot-backup must skip the nautobot_server and nautobot_jobs parts of the role and set nautobot_server_via_collection, which the role requires before it accepts either skip tag."
  }

  assert {
    condition = can(regex(
      "schedule_enabled\\s*=\\s*false",
      regex(
        "apps-nautobot-backup = \\{([^{}]*)\\}",
        file("${path.module}/../../../templates-catalog-apps-nautobot.tf")
      )[0]
    ))
    error_message = "apps-nautobot-backup must stay unscheduled; the units on the guest run the backup."
  }
}
