# Placeholder values for the run-environment variables the tau2 lanes read.
# The real values come from TF_VAR_* and are never committed.
variables {
  benchmark_client_node       = "example-node"
  benchmark_client_vmid       = "100"
  benchmark_medium_guest_vmid = "101"
  benchmark_small_guest_vmid  = "102"
  benchmark_router_url        = "https://router.example.invalid/v1"
}

run "ai_benchmark_tau2_schedule_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  assert {
    condition = alltrue([
      can(regex(
        "ai-benchmark-tau2-medium = \\{[\\s\\S]*?repository\\s*=\\s*\"ansible-proxmox-ai\"[\\s\\S]*?playbook\\s*=\\s*\"playbooks/benchmark-run.yml\"[\\s\\S]*?limit\\s*=\\s*\"all\"[\\s\\S]*?mutating\\s*=\\s*true[\\s\\S]*?schedule_enabled\\s*=\\s*true[\\s\\S]*?extra_args\\s*=\\s*\\[",
        file("${path.module}/../../../templates-catalog-ai-scheduled.tf")
      )),
      can(regex(
        "ai-benchmark-tau2-small = \\{[\\s\\S]*?repository\\s*=\\s*\"ansible-proxmox-ai\"[\\s\\S]*?playbook\\s*=\\s*\"playbooks/benchmark-run.yml\"[\\s\\S]*?limit\\s*=\\s*\"all\"[\\s\\S]*?mutating\\s*=\\s*true[\\s\\S]*?schedule_enabled\\s*=\\s*true[\\s\\S]*?extra_args\\s*=\\s*\\[",
        file("${path.module}/../../../templates-catalog-ai-scheduled.tf")
      )),
    ])
    error_message = "Both tau2 lanes must be mutating, scheduled ansible-proxmox-ai runs of playbooks/benchmark-run.yml against limit all."
  }

  assert {
    condition = alltrue([
      for m in regexall(
        "(node|client_vmid|gpu_guest_vmid|engine_url)=([^ \"]+)",
        file("${path.module}/../../../templates-catalog-ai-scheduled.tf")
      ) : startswith(m[1], "$${var.")
    ])
    error_message = "Every node, VMID and engine URL in a tau2 lane's extra vars must be a variable reference, never a literal value."
  }

  assert {
    condition = length(regexall(
      "(node|client_vmid|gpu_guest_vmid|engine_url)=([^ \"]+)",
      file("${path.module}/../../../templates-catalog-ai-scheduled.tf")
    )) == 8
    error_message = "Each tau2 lane must pass node, client_vmid, gpu_guest_vmid and engine_url exactly once."
  }

  assert {
    condition = can(regex(
      "ai-benchmark-tau2-medium\\s*=\\s*\"7 \\* \\* \\* \\*\"",
      file("${path.module}/../../../schedules.tf")
      )) && can(regex(
      "ai-benchmark-tau2-small\\s*=\\s*\"23 \\* \\* \\* \\*\"",
      file("${path.module}/../../../schedules.tf")
    ))
    error_message = "The tau2 lanes must run at minute 7 (medium) and minute 23 (small) of every hour, in UTC."
  }

  assert {
    condition = can(regex(
      "scheduled_mutating_templates = \\[[^\\]]*\"ai-benchmark-tau2-medium\"",
      file("${path.module}/../../../schedules.tf")
      )) && can(regex(
      "scheduled_mutating_templates = \\[[^\\]]*\"ai-benchmark-tau2-small\"",
      file("${path.module}/../../../schedules.tf")
    ))
    error_message = "Both tau2 lanes are mutating and must be named in the mutating schedule allowlist."
  }
}
