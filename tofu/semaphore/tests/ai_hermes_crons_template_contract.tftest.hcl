run "ai_hermes_crons_template_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "ai-hermes-crons = \\{[^}]*?repository\\s*=\\s*\"ansible-proxmox-ai\"[^}]*?playbook\\s*=\\s*\"playbooks/site.yml\"[^}]*?limit\\s*=\\s*\"hermes_agent_group\"[^}]*?tags\\s*=\\s*\"hermes_crons\"[^}]*?mutating\\s*=\\s*true[^}]*?schedule_enabled\\s*=\\s*false[^}]*?diff\\s*=\\s*false[^}]*?rail_sec\\s*=\\s*540",
      file("${path.module}/../../../templates-catalog-ai-hermes.tf")
    ))
    error_message = "The Hermes crons template must use site.yml, target hermes_agent_group with its dedicated tag, request a 540-second rail, and stay unscheduled."
  }

  assert {
    condition = !can(regex(
      "(?m)^\\s*ai-hermes-crons\\s*=",
      file("${path.module}/../../../schedules.tf")
    ))
    error_message = "The Hermes crons template must not have a scheduled run."
  }

  assert {
    condition = !can(regex(
      "ai-hermes-crons = \\{[^}]*?only_branch\\s*=",
      file("${path.module}/../../../templates-catalog-ai-hermes.tf")
    ))
    error_message = "The Hermes crons template must use the shared ref generation, including the develop variant."
  }
}
