run "proxmox_hardware_facts_template_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  # Every pattern runs against this one entry's body, so a neighbouring template
  # cannot satisfy it.
  assert {
    condition = alltrue([
      for p in [
        "repository\\s*=\\s*\"ansible-proxmox\"",
        "playbook\\s*=\\s*\"playbooks/hardware-facts\\.yml\"",
        "mutating\\s*=\\s*false",
        "schedule_enabled\\s*=\\s*false",
        "extra_args\\s*=\\s*\\[\\s*\\]",
      ] :
      can(regex(p, regex(
        "hardware-facts\\s*=\\s*\\{([\\s\\S]*?)\\n    \\}",
        file("${path.module}/../../../templates-catalog-proxmox-facts.tf")
      )[0]))
    ])
    error_message = "The hardware-facts template must use the facts playbook, stay read-only and remain unscheduled."
  }

  assert {
    condition = alltrue([
      for v in ["hardware_facts_hosts", "hardware_facts_output"] :
      can(regex(
        "name\\s*=\\s*\"${v}\"\\s+title\\s*=\\s*\"[^\"]*\"\\s+description\\s*=\\s*\"[^\"]*\"\\s+required\\s*=\\s*true",
        regex(
          "hardware-facts\\s*=\\s*\\{([\\s\\S]*?)\\n    \\}",
          file("${path.module}/../../../templates-catalog-proxmox-facts.tf")
        )[0]
      ))
    ])
    error_message = "The hardware-facts template must require the hosts and output survey values."
  }

  assert {
    condition = can(regex(
      "name\\s*=\\s*\"hardware_facts_output\"[\\s\\S]*?enum_values\\s*=\\s*\\{[^}]*?report\\s*=\\s*\"report\"[^}]*?artifact\\s*=\\s*\"artifact\"",
      regex(
        "hardware-facts\\s*=\\s*\\{([\\s\\S]*?)\\n    \\}",
        file("${path.module}/../../../templates-catalog-proxmox-facts.tf")
      )[0]
    ))
    error_message = "The hardware-facts template must offer exactly the report and artifact outputs."
  }
}
