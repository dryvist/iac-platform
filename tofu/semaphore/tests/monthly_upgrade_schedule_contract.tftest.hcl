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
      "apps-upgrade = \\{[\\s\\S]*?repository\\s*=\\s*\"ansible-proxmox-apps\"[\\s\\S]*?playbook\\s*=\\s*\"playbooks/upgrade\\.yml\"[\\s\\S]*?limit\\s*=\\s*\"upgrade_wave_0\"[\\s\\S]*?mutating\\s*=\\s*true[\\s\\S]*?schedule_enabled\\s*=\\s*true[\\s\\S]*?extra_args\\s*=\\s*\\[\\s*\\]",
      file("${path.module}/../../../templates-catalog-apps.tf")
    ))
    error_message = "apps-upgrade must use the guest upgrade playbook for LXC wave 0 and be scheduled."
  }

  assert {
    condition = can(regex(
      "apps-upgrade-lxc-rest = \\{[^{}]*?\\blimit\\s*=\\s*\"lxc_containers,!upgrade_wave_0,!upgrade_wave_1,!upgrade_wave_2,!upgrade_wave_3\"",
      file("${path.module}/../../../templates-catalog-apps-upgrade.tf")
    ))
    error_message = "apps-upgrade-lxc-rest must be the exact comma-form complement of waves 0 to 3 within lxc_containers."
  }

  assert {
    condition = alltrue([
      can(regex("apps-upgrade-lxc-1\\s*=\\s*\"46 6 \\* \\* 6\"", file("${path.module}/../../../schedules.tf"))),
      can(regex("apps-upgrade-lxc-2\\s*=\\s*\"47 6 \\* \\* 6\"", file("${path.module}/../../../schedules.tf"))),
      can(regex("apps-upgrade-lxc-3\\s*=\\s*\"48 6 \\* \\* 6\"", file("${path.module}/../../../schedules.tf"))),
      can(regex("apps-upgrade-lxc-rest\\s*=\\s*\"49 6 \\* \\* 6\"", file("${path.module}/../../../schedules.tf"))),
      can(regex("apps-upgrade-vms\\s*=\\s*\"51 6 \\* \\* 6\"", file("${path.module}/../../../schedules.tf"))),
    ])
    error_message = "The four LXC wave crons and the VM upgrade cron must be scheduled Saturday at 06:46, 06:47, 06:48, 06:49 and 06:51 UTC."
  }

  assert {
    condition = can(regex(
      "apps-upgrade\\s*=\\s*\"45 6 \\* \\* 6\"[\\s\\S]*?proxmox-upgrade\\s*=\\s*\"50 6 \\* \\* 6\"",
      file("${path.module}/../../../schedules.tf")
    ))
    error_message = "The Debian guest upgrade wave 0 and the Proxmox upgrade must be scheduled Saturday at 06:45 and 06:50 UTC."
  }

  assert {
    condition = can(regex(
      "splunk-weekly-update\\s*=\\s*\"40 6 \\* \\* 6\"",
      file("${path.module}/../../../schedules.tf")
    ))
    error_message = "The weekly Splunk update must be scheduled Saturday at 06:40 UTC."
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
