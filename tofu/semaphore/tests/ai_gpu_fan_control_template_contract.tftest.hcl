run "ai_gpu_fan_control_template_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = can(regex(
      "ai-gpu-fan-control\\s*=\\s*\\{[^}]*?repository\\s*=\\s*\"ansible-proxmox-ai\"[^}]*?playbook\\s*=\\s*\"playbooks/nvidia-gpu-fan-control\\.yml\"[^}]*?limit\\s*=\\s*\"llm_gpu_group,llm_gpu_legacy_group,llm_gpu_engine_llama_cpp_group,llm_gpu_engine_vllm_group,llm_gpu_engine_sglang_group\"[^}]*?tags\\s*=\\s*\"nvidia_gpu_guest_fan_control\"[^}]*?mutating\\s*=\\s*true[^}]*?schedule_enabled\\s*=\\s*false[^}]*?name\\s*=\\s*\"fan_control_guest_address\"[^}]*?required\\s*=\\s*true[^}]*?type\\s*=\\s*\"string\"",
      file("${path.module}/../../../templates-catalog-ai.tf")
    ))
    error_message = "The fan-control template must stay scoped, mutating, and unscheduled."
  }
}
