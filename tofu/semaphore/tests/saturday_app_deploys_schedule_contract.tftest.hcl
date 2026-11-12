run "saturday_app_deploys_schedule_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "apps-leantime = \\{[^{}]*?repository\\s*=\\s*\"ansible-proxmox-apps\"[^{}]*?playbook\\s*=\\s*\"playbooks/site\\.yml\"[^{}]*?limit\\s*=\\s*\"leantime_group\"[^{}]*?mutating\\s*=\\s*true[^{}]*?schedule_enabled\\s*=\\s*true[^{}]*?deployed_only\\s*=\\s*true[^{}]*?rail_sec\\s*=\\s*2400",
      file("${path.module}/../../../templates-catalog-saturday-deploys.tf")
    ))
    error_message = "apps-leantime must converge playbooks/site.yml limited to leantime_group, be mutating and scheduled, be deployed_only and carry rail_sec = 2400."
  }

  assert {
    condition = can(regex(
      "proxmox-oci-app-upgrade = \\{[^{}]*?repository\\s*=\\s*\"ansible-proxmox\"[^{}]*?playbook\\s*=\\s*\"playbooks/oci_app_upgrade\\.yml\"[^{}]*?limit\\s*=\\s*\"proxmox\"[^{}]*?mutating\\s*=\\s*true[^{}]*?schedule_enabled\\s*=\\s*true[^{}]*?rail_sec\\s*=\\s*3600",
      file("${path.module}/../../../templates-catalog-saturday-deploys.tf")
    ))
    error_message = "proxmox-oci-app-upgrade must run playbooks/oci_app_upgrade.yml limited to proxmox, be mutating and scheduled, and carry rail_sec = 3600."
  }

  assert {
    condition = can(regex(
      "local\\.ansible_templates_saturday_deploys,",
      file("${path.module}/../../../templates-catalog.tf")
    ))
    error_message = "templates-catalog.tf must merge the Saturday deploy catalog into ansible_templates."
  }

  assert {
    condition = alltrue([
      can(regex("apps-leantime\\s*=\\s*\"55 6 \\* \\* 6\"", file("${path.module}/../../../schedules.tf"))),
      can(regex("proxmox-oci-app-upgrade\\s*=\\s*\"5 7 \\* \\* 6\"", file("${path.module}/../../../schedules.tf"))),
    ])
    error_message = "apps-leantime must be scheduled Saturday at 06:55 UTC and proxmox-oci-app-upgrade at 07:05 UTC."
  }

  assert {
    condition = can(regex(
      "apps-upgrade-vms\\s*=\\s*\"51 6 \\* \\* 6\"[\\s\\S]*?apps-leantime\\s*=\\s*\"55 6 \\* \\* 6\"[\\s\\S]*?proxmox-oci-app-upgrade\\s*=\\s*\"5 7 \\* \\* 6\"",
      file("${path.module}/../../../schedules.tf")
    ))
    error_message = "The Saturday app deploys must be scheduled after the upgrade waves, with apps-leantime before proxmox-oci-app-upgrade."
  }

  assert {
    condition = alltrue([
      can(regex("scheduled_mutating_templates = \\[[^\\]]*\"apps-leantime\"", file("${path.module}/../../../schedules.tf"))),
      can(regex("scheduled_mutating_templates = \\[[^\\]]*\"proxmox-oci-app-upgrade\"", file("${path.module}/../../../schedules.tf"))),
    ])
    error_message = "The schedule guard must explicitly allow apps-leantime and proxmox-oci-app-upgrade as mutating schedules."
  }
}
