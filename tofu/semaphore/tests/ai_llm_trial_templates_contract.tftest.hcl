run "ai_llm_trial_templates_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "ai-llm-gpu-container-trial = \\{[^}]*?repository\\s*=\\s*\"ansible-proxmox-ai\"[^}]*?playbook\\s*=\\s*\"playbooks/llm-gpu-container-trial\\.yml\"[^}]*?limit\\s*=\\s*\"llm-blackwell-7-96GB-small\"[^}]*?only_branch\\s*=\\s*\"develop\"[^}]*?mutating\\s*=\\s*true[^}]*?schedule_enabled\\s*=\\s*false[^}]*?extra_args\\s*=\\s*\\[\"llm_gpu_container_trial_hosts=llm-blackwell-7-96GB-small\"\\]",
      file("${path.module}/../../../templates-catalog-ai-trial.tf")
    ))
    error_message = "The container-runtime template must target only the trial guest, from develop, unscheduled."
  }

  assert {
    condition = can(regex(
      "ai-llm-model-trial = \\{[^}]*?repository\\s*=\\s*\"ansible-proxmox-ai\"[^}]*?playbook\\s*=\\s*\"playbooks/llm-model-trial\\.yml\"[^}]*?limit\\s*=\\s*\"llm_gpu_group,llm-blackwell-7-96GB-small\"[^}]*?only_branch\\s*=\\s*\"develop\"[^}]*?mutating\\s*=\\s*true[^}]*?schedule_enabled\\s*=\\s*false",
      file("${path.module}/../../../templates-catalog-ai-trial.tf")
    ))
    error_message = "The model-trial template must limit the run to the GPU guest and the trial guest, from develop, unscheduled."
  }
}
