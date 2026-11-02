run "ai_llm_model_campaign_nightly_schedule_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "ai-llm-model-campaign-nightly = \\{[\\s\\S]*?repository\\s*=\\s*\"ansible-proxmox-ai\"[\\s\\S]*?playbook\\s*=\\s*\"playbooks/site.yml\"[\\s\\S]*?limit\\s*=\\s*\"all\"[\\s\\S]*?tags\\s*=\\s*\"model_campaign\"[\\s\\S]*?mutating\\s*=\\s*true[\\s\\S]*?schedule_enabled\\s*=\\s*true[\\s\\S]*?extra_args\\s*=\\s*\\[",
      file("${path.module}/../../../templates-catalog-ai.tf")
    ))
    error_message = "The nightly campaign must use the released AI site playbook, campaign tag, fixed values, and mutating schedule."
  }

  assert {
    condition = alltrue([
      strcontains(file("${path.module}/../../../templates-catalog-ai.tf"), "config_name=lm-eval/quick-intelligence"),
      strcontains(file("${path.module}/../../../templates-catalog-ai.tf"), "artifact_id=qwen38-27b-nvfp4"),
      strcontains(file("${path.module}/../../../templates-catalog-ai.tf"), "benchmark_endpoint_root=https://{{hostvars[machine].tofu_data.containers[machine].fqdn}}"),
      strcontains(file("${path.module}/../../../templates-catalog-ai.tf"), "benchmark_cache_path={{hostvars[machine].container_models_cache_mount_path}}"),
      strcontains(file("${path.module}/../../../templates-catalog-ai.tf"), "engine=vllm model_size=size-medium concurrency_list=4 context_list=32768 power_cap_w=325"),
    ])
    error_message = "The nightly campaign must pin one supported recipe and resolve its endpoint and cache from inventory."
  }

  assert {
    condition = can(regex(
      "ai-llm-model-campaign-nightly\\s*=\\s*\"17 2 \\* \\* \\*\"",
      file("${path.module}/../../../schedules.tf")
      )) && can(regex(
      "scheduled_mutating_templates = \\[[^\\]]*\"ai-llm-model-campaign-nightly\"",
      file("${path.module}/../../../schedules.tf")
    ))
    error_message = "The nightly campaign must have its UTC cron and appear in the mutating schedule allowlist."
  }

  assert {
    condition = can(regex(
      "!t\\.mutating \\|\\| contains\\(local\\.scheduled_mutating_templates, k\\)",
      file("${path.module}/../../../schedules.tf")
      )) && can(regex(
      "try\\(local\\.ansible_template_refs\\[k\\]\\.deployed, false\\)",
      file("${path.module}/../../../schedules.tf")
    ))
    error_message = "The schedule guard must retain mutating-template and released-ref checks."
  }
}
