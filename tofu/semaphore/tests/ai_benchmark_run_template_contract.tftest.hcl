run "ai_benchmark_run_template_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "ai-benchmark-run\\s*=\\s*\\{[\\s\\S]*?repository\\s*=\\s*\\\"ansible-proxmox-ai\\\"[\\s\\S]*?playbook\\s*=\\s*\\\"playbooks/benchmark-run\\.yml\\\"[\\s\\S]*?limit\\s*=\\s*\\\"all\\\"[\\s\\S]*?mutating\\s*=\\s*true[\\s\\S]*?schedule_enabled\\s*=\\s*false[\\s\\S]*?rail_sec\\s*=\\s*3600",
      file("${path.module}/../../../templates-catalog-ai.tf")
    ))
    error_message = "The benchmark-run template must use the AI playbook and a bounded unscheduled task rail."
  }

  assert {
    condition = alltrue([
      for v in ["node", "client_vmid", "engine_url", "model", "tokenizer", "suite", "items_file", "reasoning_arm", "concurrency", "max_tokens", "sandbox_pool", "input_tokens", "request_rate", "num_prompts", "seed", "run_id", "publish"] :
      can(regex(
        "name\\s*=\\s*\\\"${v}\\\"[\\s\\S]*?required\\s*=\\s*(true|false)[\\s\\S]*?type\\s*=\\s*\\\"(string|enum)\\\"",
        regex(
          "ai-benchmark-run\\s*=\\s*\\{([\\s\\S]*?)\\n    \\}",
          file("${path.module}/../../../templates-catalog-ai.tf")
        )[0]
      ))
    ])
    error_message = "The benchmark-run template must expose every suite survey variable."
  }

  assert {
    condition = can(regex(
      "name\\s*=\\s*\\\"reasoning_arm\\\"[\\s\\S]*?off\\s*=\\s*\\\"off\\\"[\\s\\S]*?low\\s*=\\s*\\\"low\\\"[\\s\\S]*?xhigh\\s*=\\s*\\\"xhigh\\\"",
      file("${path.module}/../../../templates-catalog-ai.tf")
      )) && can(regex(
      "name\\s*=\\s*\\\"publish\\\"[\\s\\S]*?required\\s*=\\s*false[\\s\\S]*?\\\"false\\\"\\s*=\\s*\\\"false\\\"",
      file("${path.module}/../../../templates-catalog-ai.tf")
    ))
    error_message = "The benchmark-run survey must record a reasoning arm and leave publication disabled by default."
  }
}
