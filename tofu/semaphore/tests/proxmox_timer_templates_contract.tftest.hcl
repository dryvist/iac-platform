run "proxmox_timer_templates_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "proxmox-config-backup\\s*=\\s*\\{[^}]*?repository\\s*=\\s*\"ansible-proxmox\"[^}]*?playbook\\s*=\\s*\"playbooks/site\\.yml\"[^}]*?limit\\s*=\\s*\"proxmox\"[^}]*?tags\\s*=\\s*\"pve_config_backup\"[^}]*?mutating\\s*=\\s*true[^}]*?schedule_enabled\\s*=\\s*false[^}]*?only_branch\\s*=\\s*\"develop\"",
      file("${path.module}/../../../templates-catalog-proxmox-timers.tf")
    ))
    error_message = "The Proxmox config-backup template must be tagged, mutating, unscheduled, and develop-only."
  }

  assert {
    condition = can(regex(
      "proxmox-postgres-standby\\s*=\\s*\\{[^}]*?repository\\s*=\\s*\"ansible-proxmox\"[^}]*?playbook\\s*=\\s*\"playbooks/site\\.yml\"[^}]*?limit\\s*=\\s*\"proxmox\"[^}]*?tags\\s*=\\s*\"postgres_standby\"[^}]*?mutating\\s*=\\s*true[^}]*?schedule_enabled\\s*=\\s*false[^}]*?only_branch\\s*=\\s*\"develop\"",
      file("${path.module}/../../../templates-catalog-proxmox-timers.tf")
    ))
    error_message = "The Proxmox Postgres standby template must be tagged, mutating, unscheduled, and develop-only."
  }

  assert {
    condition = can(regex(
      "proxmox-backup-jobs\\s*=\\s*\\{[^}]*?repository\\s*=\\s*\"ansible-proxmox\"[^}]*?playbook\\s*=\\s*\"playbooks/site\\.yml\"[^}]*?limit\\s*=\\s*\"proxmox\"[^}]*?tags\\s*=\\s*\"pve_backup_jobs\"[^}]*?mutating\\s*=\\s*true[^}]*?schedule_enabled\\s*=\\s*false[^}]*?only_branch\\s*=\\s*\"develop\"",
      file("${path.module}/../../../templates-catalog-proxmox-timers.tf")
    ))
    error_message = "The Proxmox backup-jobs template must be tagged, mutating, unscheduled, and develop-only."
  }

  assert {
    condition = can(regex(
      "proxmox-zfs-scrub-window\\s*=\\s*\\{[^}]*?repository\\s*=\\s*\"ansible-proxmox\"[^}]*?playbook\\s*=\\s*\"playbooks/site\\.yml\"[^}]*?limit\\s*=\\s*\"proxmox\"[^}]*?tags\\s*=\\s*\"zfs_scrub_window\"[^}]*?mutating\\s*=\\s*true[^}]*?schedule_enabled\\s*=\\s*false[^}]*?only_branch\\s*=\\s*\"develop\"",
      file("${path.module}/../../../templates-catalog-proxmox-timers.tf")
    ))
    error_message = "The Proxmox ZFS scrub-window template must be tagged, mutating, unscheduled, and develop-only."
  }

  assert {
    condition     = strcontains(file("${path.module}/../../../templates-catalog.tf"), "local.ansible_templates_proxmox_timers")
    error_message = "The Proxmox timer template map must be merged into the Semaphore catalog."
  }
}
