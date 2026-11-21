run "apps_github_runner_schedule" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "apps-github-runner = \\{[^}]*?limit\\s*=\\s*\"docker_vms\"[^}]*?tags\\s*=\\s*\"github_runner\"[^}]*?mutating\\s*=\\s*true[^}]*?schedule_enabled\\s*=\\s*true",
      file("${path.module}/../../../templates-catalog-apps.tf")
    ))
    error_message = "The runner converge template must be scheduled and scoped to docker_vms with the github_runner tag."
  }

  # The runner converge must follow every scheduled AppRole rotation run.
  assert {
    condition = (
      can(regex("cron_format = \"13 3,15 \\* \\* \\*\"", file("${path.module}/../../../schedules.tf"))) &&
      can(regex("apps-github-runner\\s*=\\s*\"43 3,15 \\* \\* \\*\"", file("${path.module}/../../../schedules.tf")))
    )
    error_message = "The runner converge must run at 43 3,15 * * *, 30 minutes after the AppRole rotation at 13 3,15 * * *."
  }

  assert {
    condition = can(regex(
      "scheduled_mutating_templates = \\[[^\\]]*\"apps-github-runner\"",
      file("${path.module}/../../../schedules.tf")
    ))
    error_message = "The schedule guard must explicitly allow the runner converge as a mutating schedule."
  }
}
