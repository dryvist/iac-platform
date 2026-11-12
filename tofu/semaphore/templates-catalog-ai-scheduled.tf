# Scheduled ansible-proxmox-ai templates. Kept apart from the on-demand
# catalog to keep both Terraform files below the repository size gate.

locals {
  # Suite id the benchmark-run playbook accepts for tau2; each lane picks its
  # domain through tau2_domain.
  benchmark_tau2_suite = "tau2-banking-knowledge"

  # One entry per tau2 benchmark lane. Each lane becomes one scheduled template
  # named ai-benchmark-tau2-<name>, and schedules.tf reads its cron from here.
  # guest_key names the lane's entry in the benchmark_lane_guest_vmids variable.
  benchmark_tau2_lanes = [
    {
      name            = "medium"
      model           = "medium"
      tau2_domain     = "banking_knowledge"
      concurrency     = 10
      tau2_num_trials = 1
      cron            = "7 * * * *"
      rail_sec        = 3300
      guest_key       = "medium"
    },
    {
      name            = "small"
      model           = "small"
      tau2_domain     = "retail"
      concurrency     = 2
      tau2_num_trials = 1
      cron            = "23 * * * *"
      rail_sec        = 3300
      guest_key       = "small"
    },
  ]

  # Template name -> lane. The only place a lane's template name is built.
  benchmark_tau2_templates = {
    for lane in local.benchmark_tau2_lanes : "ai-benchmark-tau2-${lane.name}" => lane
  }

  ansible_templates_ai_scheduled_fixed = {
    ai-laya-finetune-collect = {
      repository       = "ansible-proxmox-ai"
      playbook         = "playbooks/site.yml"
      limit            = "llm_classify"
      tags             = "laya_systemone"
      mutating         = true
      schedule_enabled = false
      extra_args = [
        "--extra-vars",
        "laya_systemone_finetune_enabled=true laya_systemone_finetune_action=collect",
      ]
      description = "Collect detached Laya fine-tune jobs and restore services."
    }

    # Fixed inputs keep the unattended run to one recipe on the medium vLLM
    # lane. The wrapper appends localhost to the selected target limit.
    ai-llm-model-campaign-nightly = {
      repository       = "ansible-proxmox-ai"
      playbook         = "playbooks/site.yml"
      limit            = "llm-blackwell-7-96GB-medium"
      tags             = "model_campaign"
      mutating         = true
      schedule_enabled = true
      extra_args = [
        "--extra-vars",
        "config_name=lm-eval/quick-intelligence artifact_id=qwen38-27b-nvfp4 machine=llm-blackwell-7-96GB-medium benchmark_endpoint_root=https://{{hostvars[machine].tofu_data.containers[machine].fqdn}} benchmark_cache_path={{hostvars[machine].container_models_cache_mount_path}} engine=vllm model_size=size-medium concurrency_list=4 context_list=32768 power_cap_w=325",
      ]
      description = "Run the quick-intelligence quality recipe hourly on the medium vLLM lane."
    }
  }

  # The fixed entries above and one generated template per tau2 lane, merged the
  # same way templates-catalog.tf merges the per-repository maps. Every lane
  # shares one extra-vars builder; only the lane's own values differ. The
  # tokenizer comes from the benchmark_model_tokenizers variable, keyed by the
  # lane's model alias.
  ansible_templates_ai_scheduled = merge(local.ansible_templates_ai_scheduled_fixed, {
    for tname, lane in local.benchmark_tau2_templates : tname => {
      repository       = "ansible-proxmox-ai"
      playbook         = "playbooks/benchmark-run.yml"
      limit            = "all"
      mutating         = true
      schedule_enabled = true
      rail_sec         = lane.rail_sec
      extra_args = [
        "--extra-vars",
        join(" ", [
          for k, v in {
            suite                = local.benchmark_tau2_suite
            tau2_domain          = lane.tau2_domain
            tau2_max_concurrency = lane.concurrency
            tau2_num_trials      = lane.tau2_num_trials
            concurrency          = lane.concurrency
            model                = lane.model
            tokenizer            = var.benchmark_model_tokenizers[lane.model]
            upgrade              = "false"
            publish              = "false"
            api_key_kv_path      = var.benchmark_api_key_kv_path
            api_key_kv_field     = var.benchmark_api_key_kv_field
            run_id               = "tau2-${lane.name}-{{now(utc=true,fmt='%Y%m%dT%H%M')}}"
            node                 = var.benchmark_client_node
            client_vmid          = var.benchmark_client_vmid
            gpu_guest_vmid       = var.benchmark_lane_guest_vmids[lane.guest_key]
            engine_url           = var.benchmark_router_url
          } : "${k}=${v}"
        ]),
      ]
      description = "Run the tau2 ${replace(lane.tau2_domain, "_", "-")} suite hourly on the ${lane.name} lane."
    }
  })
}
