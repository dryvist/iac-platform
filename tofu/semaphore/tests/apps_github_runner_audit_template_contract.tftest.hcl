run "apps_github_runner_audit_template_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "apps-github-runner-audit\\s*=\\s*\\{[^}]*?repository\\s*=\\s*\"ansible-proxmox-apps\"[^}]*?playbook\\s*=\\s*\"playbooks/site\\.yml\"[^}]*?limit\\s*=\\s*\"docker_vms\"[^}]*?tags\\s*=\\s*\"runner_container_audit\"",
      file("${path.module}/../../../templates-catalog-apps-runner-audit.tf")
    ))
    error_message = "The runner audit template must run site.yml on docker_vms scoped to runner_container_audit."
  }

  assert {
    condition = can(regex(
      "apps-github-runner-audit\\s*=\\s*\\{[^}]*?mutating\\s*=\\s*false[^}]*?schedule_enabled\\s*=\\s*false[^}]*?extra_args\\s*=\\s*\\[\\s*\\]",
      file("${path.module}/../../../templates-catalog-apps-runner-audit.tf")
    ))
    error_message = "The runner audit template must be non-mutating, unscheduled and use no extra arguments."
  }

  assert {
    condition = can(regex(
      "local\\.ansible_templates_apps_runner_audit,",
      file("${path.module}/../../../templates-catalog.tf")
    ))
    error_message = "The runner audit catalog must be merged into ansible_templates."
  }
}
