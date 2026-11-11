# Placeholder values for the run-environment variables the tau2 lanes read.
# The real values come from TF_VAR_* and are never committed.
variables {
  benchmark_client_node      = "example-node"
  benchmark_client_vmid      = "100"
  benchmark_router_url       = "https://router.example.invalid/v1"
  benchmark_lane_guest_vmids = { medium = "101", small = "102" }
}

run "ai_benchmark_tau2_schedule_contract" {
  command = plan

  module {
    source = "./tests/fixtures/noop"
  }

  # The per-lane checks below are vacuous on an empty list, so require one lane.
  assert {
    condition = length(regexall(
      "name\\s*=\\s*\"([a-z0-9-]+)\"[^{}]*?\\brail_sec\\s*=\\s*([0-9]+)",
      file("${path.module}/../../../templates-catalog-ai-scheduled.tf")
    )) > 0
    error_message = "The benchmark lane list must name at least one lane."
  }

  # Each lane is read from the lane list itself, so this check runs once per
  # lane and adding a lane needs no change here.
  assert {
    condition = alltrue([
      for lane in regexall(
        "name\\s*=\\s*\"([a-z0-9-]+)\"[^{}]*?\\brail_sec\\s*=\\s*([0-9]+)",
        file("${path.module}/../../../templates-catalog-ai-scheduled.tf")
        ) : alltrue([
          for check in [
            "\\bmodel\\s*=\\s*\"[a-z]+\"",
            "\\btokenizer\\s*=\\s*\"[^\"]+\"",
            "\\btau2_domain\\s*=\\s*\"[a-z_]+\"",
            "\\bconcurrency\\s*=\\s*[0-9]+",
            "\\btau2_num_trials\\s*=\\s*[0-9]+",
            "\\bcron\\s*=\\s*\"[0-9]+ \\* \\* \\* \\*\"",
            "\\brail_sec\\s*=\\s*[0-9]+",
            "\\bguest_key\\s*=\\s*\"[a-z0-9-]+\"",
            ] : can(regex(check, regex(
              "name\\s*=\\s*\"${lane[0]}\"[^{}]*",
              file("${path.module}/../../../templates-catalog-ai-scheduled.tf")
          )))
      ])
    ])
    error_message = "Every benchmark lane must set model, tokenizer, tau2_domain, concurrency, tau2_num_trials, cron (hourly), rail_sec and guest_key."
  }

  # One builder generates every tau2 template. It must keep the fixed shape and
  # take every node, VMID, URL and key path from a variable, never a literal.
  assert {
    condition = alltrue([
      can(regex(
        "ansible_templates_ai_scheduled = merge\\(local\\.ansible_templates_ai_scheduled_fixed, \\{",
        file("${path.module}/../../../templates-catalog-ai-scheduled.tf")
      )),
      can(regex(
        "\"ai-benchmark-tau2-\\$\\{lane\\.name\\}\" => lane",
        file("${path.module}/../../../templates-catalog-ai-scheduled.tf")
      )),
      can(regex(
        "tname => \\{\\s*repository\\s*=\\s*\"ansible-proxmox-ai\"\\s*playbook\\s*=\\s*\"playbooks/benchmark-run\\.yml\"\\s*limit\\s*=\\s*\"all\"\\s*mutating\\s*=\\s*true\\s*schedule_enabled\\s*=\\s*true\\s*rail_sec\\s*=\\s*lane\\.rail_sec",
        file("${path.module}/../../../templates-catalog-ai-scheduled.tf")
      )),
      can(regex("\\bnode\\s*=\\s*var\\.benchmark_client_node\\b", file("${path.module}/../../../templates-catalog-ai-scheduled.tf"))),
      can(regex("\\bclient_vmid\\s*=\\s*var\\.benchmark_client_vmid\\b", file("${path.module}/../../../templates-catalog-ai-scheduled.tf"))),
      can(regex("\\bgpu_guest_vmid\\s*=\\s*var\\.benchmark_lane_guest_vmids\\[lane\\.guest_key\\]", file("${path.module}/../../../templates-catalog-ai-scheduled.tf"))),
      can(regex("\\bengine_url\\s*=\\s*var\\.benchmark_router_url\\b", file("${path.module}/../../../templates-catalog-ai-scheduled.tf"))),
      can(regex("\\bapi_key_kv_path\\s*=\\s*var\\.benchmark_api_key_kv_path\\b", file("${path.module}/../../../templates-catalog-ai-scheduled.tf"))),
      can(regex("\\bapi_key_kv_field\\s*=\\s*var\\.benchmark_api_key_kv_field\\b", file("${path.module}/../../../templates-catalog-ai-scheduled.tf"))),
      can(regex(
        "\"tau2-\\$\\{lane\\.name\\}-\\{\\{ now\\(utc=true, fmt='%Y%m%dT%H%M'\\) \\}\\}\"",
        file("${path.module}/../../../templates-catalog-ai-scheduled.tf")
      )),
    ])
    error_message = "The tau2 builder must keep the fixed batch shape and read node, client VMID, guest VMID, router URL and key path from variables."
  }

  assert {
    condition = !can(regex(
      "\\b(node|client_vmid|gpu_guest_vmid|engine_url|api_key_kv_path|api_key_kv_field)\\s*=\\s*\"",
      file("${path.module}/../../../templates-catalog-ai-scheduled.tf")
    ))
    error_message = "No tau2 lane may pass a node, VMID, URL or key path as a literal string."
  }

  # The mutating allowlist and the cron map both derive from the lane list.
  assert {
    condition = alltrue([
      can(regex(
        "scheduled_mutating_templates = concat\\(\\[[\\s\\S]*?\\], keys\\(local\\.benchmark_tau2_templates\\)\\)",
        file("${path.module}/../../../schedules.tf")
      )),
      can(regex(
        "schedule_crons = merge\\(\\{[\\s\\S]*?\\}, \\{\\s*for tname, lane in local\\.benchmark_tau2_templates : tname => lane\\.cron\\s*\\}\\)",
        file("${path.module}/../../../schedules.tf")
      )),
    ])
    error_message = "The mutating allowlist and the cron map must both derive from the benchmark lane list."
  }

  assert {
    condition = can(regex(
      "contains\\(keys\\(var\\.benchmark_lane_guest_vmids\\), lane\\.guest_key\\)",
      file("${path.module}/../../../schedules.tf")
    ))
    error_message = "The schedule guard must fail when a lane's guest_key is missing from benchmark_lane_guest_vmids."
  }
}
