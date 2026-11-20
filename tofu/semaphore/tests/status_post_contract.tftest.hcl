# Status posts: one template and one schedule per entry of local.status_posts,
# each selecting its post with -e status_post=<key>, on the deployed ref, with
# the schedule gated by recurring_jobs_enabled and on odd minutes.

run "status_post_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }


  assert {
    condition = can(regex(
      "arguments\\s*=\\s*\\[\\s*\"\\./scripts/run-ansible\\.sh\", \"playbooks/status-post\\.yml\",\\s*\"-i\", \"localhost,\",\\s*\"--limit\", \"localhost\",\\s*\"-e\", \"status_post=\\$\\{each\\.key\\}\",?\\s*\\]",
      file("${path.module}/../../../templates-status-post.tf")
    ))
    error_message = "status_post must pass exactly playbooks/status-post.yml with -i localhost, --limit localhost and -e status_post=<key>."
  }

  assert {
    condition = alltrue([
      can(regex("resource \"semaphoreui_project_template\" \"status_post\" \\{\\s*for_each\\s*=\\s*local\\.status_posts", file("${path.module}/../../../templates-status-post.tf"))),
      can(regex("resource \"semaphoreui_project_schedule\" \"status_post\" \\{\\s*for_each\\s*=\\s*local\\.status_posts", file("${path.module}/../../../templates-status-post.tf"))),
    ])
    error_message = "The status_post template and schedule must both iterate local.status_posts."
  }

  assert {
    condition = can(regex(
      "view_id\\s*=\\s*semaphoreui_project_view[.]each\\[\"apps/deployed\"\\][.]id",
      file("${path.module}/../../../templates-status-post.tf")
    ))
    error_message = "status_post must use the deployed-ref view."
  }

  assert {
    condition = can(regex(
      "cron_format\\s*=\\s*each\\.value\\s*enabled\\s*=\\s*var\\.recurring_jobs_enabled",
      file("${path.module}/../../../templates-status-post.tf")
    ))
    error_message = "status_post schedules must be enabled by the recurring_jobs_enabled variable, not hardcoded."
  }

  assert {
    condition     = !can(regex("(?i)(token|secret|password|api[_-]?key|ghp_|github_pat_)", file("${path.module}/../../../templates-status-post.tf")))
    error_message = "status_post's declaration must be secret-free; its inputs reach the playbook through the run environment."
  }

  assert {
    condition = alltrue([
      for minute in flatten([
        for cron in regexall("= \"([0-9,]+) \\* \\* \\* \\*\"", file("${path.module}/../../../templates-status-post.tf")) : split(",", cron[0])
      ]) : tonumber(minute) % 2 == 1 && tonumber(minute) % 15 != 0
    ]) && length(regexall("= \"([0-9,]+) \\* \\* \\* \\*\"", file("${path.module}/../../../templates-status-post.tf"))) > 0
    error_message = "Every status post cron must run hourly on odd minutes only, never on a quarter-hour mark."
  }
}
