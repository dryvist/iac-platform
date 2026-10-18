run "monthly_upgrade_schedule_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "proxmox-upgrade = \\{[\\s\\S]*?repository\\s*=\\s*\"ansible-proxmox\"[\\s\\S]*?playbook\\s*=\\s*\"playbooks/upgrade\\.yml\"[\\s\\S]*?limit\\s*=\\s*\"proxmox\"[\\s\\S]*?mutating\\s*=\\s*true[\\s\\S]*?schedule_enabled\\s*=\\s*true[\\s\\S]*?extra_args\\s*=\\s*\\[\\s*\\]",
      file("${path.module}/../../../templates-catalog-proxmox.tf")
    ))
    error_message = "proxmox-upgrade must use the Proxmox upgrade playbook and be scheduled."
  }

  assert {
    condition = can(regex(
      "name\\s*=\\s*\"upgrade_nodes\"[\\s\\S]*?description\\s*=\\s*\"Node name\\(s\\) to upgrade; blank defaults to all Proxmox nodes\\.\"[\\s\\S]*?required\\s*=\\s*false[\\s\\S]*?type\\s*=\\s*\"string\"",
      file("${path.module}/../../../templates-catalog-proxmox.tf")
    ))
    error_message = "The optional upgrade_nodes survey variable must default to all Proxmox nodes."
  }

  assert {
    condition = can(regex(
      "apps-upgrade = \\{[\\s\\S]*?repository\\s*=\\s*\"ansible-proxmox-apps\"[\\s\\S]*?playbook\\s*=\\s*\"playbooks/upgrade\\.yml\"[\\s\\S]*?limit\\s*=\\s*\"all\"[\\s\\S]*?mutating\\s*=\\s*true[\\s\\S]*?schedule_enabled\\s*=\\s*true[\\s\\S]*?extra_args\\s*=\\s*\\[\\s*\\]",
      file("${path.module}/../../../templates-catalog-apps.tf")
    ))
    error_message = "apps-upgrade must use the guest upgrade playbook and be scheduled."
  }

  assert {
    condition = can(regex(
      "apps-upgrade\\s*=\\s*\"30 14 \\* \\* 6\"[\\s\\S]*?proxmox-upgrade\\s*=\\s*\"0 14 \\* \\* 6\"",
      file("${path.module}/../../../schedules.tf")
    ))
    error_message = "The Proxmox and Debian guest upgrades must be scheduled on Saturday at their specified times."
  }

  assert {
    condition = can(regex(
      "contains\\(local\\.scheduled_mutating_templates, k\\)",
      file("${path.module}/../../../schedules.tf")
      )) && can(regex(
      "join\\(.*local\\.scheduled_mutating_templates",
      file("${path.module}/../../../schedules.tf")
    ))
    error_message = "The mutating schedule guard must explicitly allow both monthly upgrade templates by name."
  }
}
