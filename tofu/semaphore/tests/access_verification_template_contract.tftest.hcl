run "access_verification_template_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "proxmox-access-verification\\s*=\\s*\\{[^}]*?repository\\s*=\\s*\"ansible-proxmox\"[^}]*?playbook\\s*=\\s*\"tests/access_verification/verify\\.yml\"[^}]*?limit\\s*=\\s*\"proxmox\"",
      file("${path.module}/../../../templates-catalog-proxmox.tf")
    ))
    error_message = "The access verification template must target its live verification playbook."
  }

  assert {
    condition = can(regex(
      "proxmox-access-verification\\s*=\\s*\\{[^}]*?mutating\\s*=\\s*false[^}]*?schedule_enabled\\s*=\\s*false[^}]*?extra_args\\s*=\\s*\\[\\s*\\]",
      file("${path.module}/../../../templates-catalog-proxmox.tf")
    ))
    error_message = "The access verification template must be non-mutating, unscheduled and use no extra arguments."
  }
}
