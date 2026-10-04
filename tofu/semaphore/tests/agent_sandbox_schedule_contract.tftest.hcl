run "agent_sandbox_credentials_schedule" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "apps-agent-sandbox-credentials = \\{[\\s\\S]*?repository\\s*=\\s*\"ansible-proxmox-apps\"[\\s\\S]*?playbook\\s*=\\s*\"playbooks/site.yml\"[\\s\\S]*?limit\\s*=\\s*\"agent_sandbox_host\"[\\s\\S]*?tags\\s*=\\s*\"agent_sandbox_credentials\"[\\s\\S]*?mutating\\s*=\\s*true[\\s\\S]*?schedule_enabled\\s*=\\s*true",
      file("${path.module}/../../../templates-catalog-apps-site-split.tf")
    ))
    error_message = "The scheduled sandbox template must target the sandbox group and credential tag."
  }

  assert {
    condition = can(regex(
      "apps-agent-sandbox-credentials\\s*=\\s*\"13 4,16 \\* \\* \\*\"",
      file("${path.module}/../../../schedules.tf")
    ))
    error_message = "The sandbox schedule must run at 13 4,16 * * *."
  }

  assert {
    condition = can(regex(
      "!t[.]mutating \\|\\| contains\\([\\s\\S]*?splunk-weekly-update[\\s\\S]*?apps-agent-sandbox-credentials[\\s\\S]*?k",
      file("${path.module}/../../../schedules.tf")
    ))
    error_message = "The schedule guard must explicitly allow the scoped sandbox template as a mutating schedule."
  }
}
