run "proxmox_fan_control_template_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "proxmox-fan-control\\s*=\\s*\\{[^}]*?repository\\s*=\\s*\"ansible-proxmox\"[^}]*?playbook\\s*=\\s*\"playbooks/site\\.yml\"[^}]*?limit\\s*=\\s*\"proxmox\"[^}]*?tags\\s*=\\s*\"fan_control\"[^}]*?mutating\\s*=\\s*true[^}]*?schedule_enabled\\s*=\\s*false[^}]*?extra_args\\s*=\\s*\\[\"--extra-vars\",\\s*\"fan_control=true fan_control_active_mode=benchmark-100\"\\][^}]*?only_branch\\s*=\\s*\"develop\"",
      file("${path.module}/../../../templates-catalog-proxmox.tf")
    ))
    error_message = "The fan-control template must stay tagged, mutating, unscheduled, benchmark-100, and develop-only."
  }
}
