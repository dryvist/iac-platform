run "proxmox_benchmark_client_template_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "proxmox-benchmark-client\\s*=\\s*\\{[\\s\\S]*?repository\\s*=\\s*\"ansible-proxmox\"[\\s\\S]*?playbook\\s*=\\s*\"playbooks/benchmark-client\\.yml\"[\\s\\S]*?limit\\s*=\\s*\"proxmox\"[\\s\\S]*?mutating\\s*=\\s*true[\\s\\S]*?schedule_enabled\\s*=\\s*false[\\s\\S]*?extra_args\\s*=\\s*\\[\\s*\\]",
      file("${path.module}/../../../templates-catalog-proxmox.tf")
    ))
    error_message = "The benchmark-client template must use the client playbook and remain unscheduled and mutating."
  }

  assert {
    condition = alltrue([
      for v in ["node", "vmid", "gpu_guest_vmid", "state", "cores", "memory_mb", "disk_gb", "template", "images", "tools", "engine_url"] :
      can(regex(
        "name\\s*=\\s*\"${v}\"\\s+title\\s*=\\s*\"[^\"]*\"\\s+description\\s*=\\s*\"[^\"]*\"\\s+required\\s*=\\s*(true|false)",
        regex(
          "proxmox-benchmark-client\\s*=\\s*\\{([\\s\\S]*?)\\n    \\}",
          file("${path.module}/../../../templates-catalog-proxmox.tf")
        )[0]
      ))
    ])
    error_message = "The benchmark-client template must expose each lifecycle survey variable."
  }

  assert {
    condition = alltrue([
      can(regex(
        "name\\s*=\\s*\"state\"[\\s\\S]*?enum_values\\s*=\\s*\\{[^}]*?present\\s*=\\s*\"present\"[^}]*?absent\\s*=\\s*\"absent\"",
        regex(
          "proxmox-benchmark-client\\s*=\\s*\\{([\\s\\S]*?)\\n    \\}",
          file("${path.module}/../../../templates-catalog-proxmox.tf")
        )[0]
      )),
      alltrue([
        for v in ["node", "vmid", "gpu_guest_vmid", "state"] :
        can(regex(
          "name\\s*=\\s*\"${v}\"\\s+title\\s*=\\s*\"[^\"]*\"\\s+description\\s*=\\s*\"[^\"]*\"\\s+required\\s*=\\s*true",
          regex(
            "proxmox-benchmark-client\\s*=\\s*\\{([\\s\\S]*?)\\n    \\}",
            file("${path.module}/../../../templates-catalog-proxmox.tf")
          )[0]
        ))
      ])
    ])
    error_message = "The benchmark-client template must offer present/absent and require its target identifiers."
  }
}

run "proxmox_benchmark_upgrade_template_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "proxmox-benchmark-upgrade\\s*=\\s*\\{[\\s\\S]*?repository\\s*=\\s*\"ansible-proxmox\"[\\s\\S]*?playbook\\s*=\\s*\"playbooks/upgrade\\.yml\"[\\s\\S]*?limit\\s*=\\s*\"localhost\"[\\s\\S]*?mutating\\s*=\\s*true[\\s\\S]*?schedule_enabled\\s*=\\s*false[\\s\\S]*?rail_sec\\s*=\\s*3600",
      file("${path.module}/../../../templates-catalog-proxmox.tf")
    ))
    error_message = "The benchmark upgrade template must run the existing rolling playbook and remain unscheduled and mutating."
  }
}
