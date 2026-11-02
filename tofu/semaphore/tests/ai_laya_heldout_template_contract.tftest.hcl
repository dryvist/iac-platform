run "ai_laya_heldout_template_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "ai-laya-heldout = \\{[^}]*?repository\\s*=\\s*\"ansible-proxmox-ai\"[^}]*?playbook\\s*=\\s*\"playbooks/site.yml\"[^}]*?limit\\s*=\\s*\"llm_classify\"[^}]*?tags\\s*=\\s*\"laya_systemone_heldout\"[^}]*?mutating\\s*=\\s*true[^}]*?rail_sec\\s*=\\s*540[^}]*?schedule_enabled\\s*=\\s*false",
      file("${path.module}/../../../templates-catalog-ai.tf")
    ))
    error_message = "The Laya held-out template must use site.yml, target llm_classify with its dedicated tag, request a 540-second rail, and stay unscheduled."
  }

  assert {
    condition = !can(regex(
      "(?m)^\\s*ai-laya-heldout\\s*=",
      file("${path.module}/../../../schedules.tf")
    ))
    error_message = "The Laya held-out template must not have a scheduled run."
  }

  assert {
    condition = !can(regex(
      "ai-laya-heldout = \\{[^}]*?only_branch\\s*=",
      file("${path.module}/../../../templates-catalog-ai.tf")
    ))
    error_message = "The Laya held-out template must use the shared ref generation, including the develop variant."
  }
}
