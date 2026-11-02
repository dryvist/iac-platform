run "ai_laya_finetune_collect_schedule_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "ai-laya-finetune-collect = \\{[^}]*?repository\\s*=\\s*\"ansible-proxmox-ai\"[^}]*?playbook\\s*=\\s*\"playbooks/site.yml\"[^}]*?limit\\s*=\\s*\"llm_classify\"[^}]*?tags\\s*=\\s*\"laya_systemone\"[^}]*?mutating\\s*=\\s*true[^}]*?schedule_enabled\\s*=\\s*true[^}]*?extra_args\\s*=\\s*\\[\\s*\"--extra-vars\",\\s*\"laya_systemone_finetune_enabled=true laya_systemone_finetune_action=collect\"",
      file("${path.module}/../../../templates-catalog-ai-scheduled.tf")
    ))
    error_message = "The Laya collect template must target the classifier group and run only the collect action."
  }

  assert {
    condition = can(regex(
      "ai-laya-finetune-collect\\s*=\\s*\"9,24,39,54 \\* \\* \\* \\*\"",
      file("${path.module}/../../../schedules.tf")
    ))
    error_message = "The Laya collect schedule must run every 15 minutes at an offset cron."
  }

  assert {
    condition = can(regex(
      "scheduled_mutating_templates = \\[[^\\]]*\"ai-laya-finetune-collect\"",
      file("${path.module}/../../../schedules.tf")
    ))
    error_message = "The scheduled Laya collect template must be explicitly allowed as mutating."
  }
}
