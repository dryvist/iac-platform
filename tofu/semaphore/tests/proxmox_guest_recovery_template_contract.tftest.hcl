run "proxmox_guest_recovery_template_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "proxmox-guest-recovery\\s*=\\s*\\{[\\s\\S]*?repository\\s*=\\s*\"ansible-proxmox\"[\\s\\S]*?playbook\\s*=\\s*\"playbooks/guest-recovery\\.yml\"[\\s\\S]*?limit\\s*=\\s*\"proxmox\"[\\s\\S]*?mutating\\s*=\\s*true[\\s\\S]*?schedule_enabled\\s*=\\s*false[\\s\\S]*?extra_args\\s*=\\s*\\[\\s*\\]",
      file("${path.module}/../../../templates-catalog-proxmox.tf")
    ))
    error_message = "The guest-recovery template must use the recovery playbook and remain unscheduled and mutating."
  }

  assert {
    condition = alltrue([
      for v in ["node", "vmid", "mode", "reason"] :
      can(regex(
        "name\\s*=\\s*\"${v}\"\\s+title\\s*=\\s*\"[^\"]*\"\\s+description\\s*=\\s*\"[^\"]*\"\\s+required\\s*=\\s*true",
        regex(
          "proxmox-guest-recovery\\s*=\\s*\\{([\\s\\S]*?)\\n    \\}",
          file("${path.module}/../../../templates-catalog-proxmox.tf")
        )[0]
      ))
    ])
    error_message = "The guest-recovery template must require node, VMID, mode and reason survey values."
  }

  assert {
    condition = can(regex(
      "name\\s*=\\s*\"mode\"[\\s\\S]*?enum_values\\s*=\\s*\\{[^}]*?unit-stop\\s*=\\s*\"unit-stop\"[^}]*?unit-kill\\s*=\\s*\"unit-kill\"[^}]*?guest-restart\\s*=\\s*\"guest-restart\"",
      regex(
        "proxmox-guest-recovery\\s*=\\s*\\{([\\s\\S]*?)\\n    \\}",
        file("${path.module}/../../../templates-catalog-proxmox.tf")
      )[0]
      )) && !can(regex(
      "node-reboot",
      regex(
        "proxmox-guest-recovery\\s*=\\s*\\{([\\s\\S]*?)\\n    \\}",
        file("${path.module}/../../../templates-catalog-proxmox.tf")
      )[0]
    ))
    error_message = "The guest-recovery template must expose only its supported recovery modes."
  }
}
