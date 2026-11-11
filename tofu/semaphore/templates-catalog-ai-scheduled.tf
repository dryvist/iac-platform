# Scheduled ansible-proxmox-ai templates. Kept apart from the on-demand
# catalog to keep both Terraform files below the repository size gate.

locals {
  ansible_templates_ai_scheduled = {
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
      description = "Run the quick-intelligence quality recipe nightly on the medium vLLM lane."
    }

    # Hourly tau2 lanes, one per model size. Node, client and guest VMIDs and
    # the router URL are supplied at run time as TF_VAR_* values, never here.
    ai-benchmark-tau2-medium = {
      repository       = "ansible-proxmox-ai"
      playbook         = "playbooks/benchmark-run.yml"
      limit            = "all"
      mutating         = true
      schedule_enabled = true
      rail_sec         = 3300
      extra_args = [
        "--extra-vars",
        "suite=tau2-banking-knowledge tau2_domain=banking_knowledge tau2_max_concurrency=10 tau2_num_trials=1 concurrency=10 model=medium tokenizer=nvidia/Qwen3.8-27B-NVFP4 upgrade=false publish=false api_key_kv_path=apps/evals api_key_kv_field=evals_llm_router_key run_id=tau2-medium-{{ now(utc=true, fmt='%Y%m%dT%H%M') }} node=${var.benchmark_client_node} client_vmid=${var.benchmark_client_vmid} gpu_guest_vmid=${var.benchmark_medium_guest_vmid} engine_url=${var.benchmark_router_url}",
      ]
      description = "Run the tau2 banking-knowledge suite hourly on the medium lane."
    }

    ai-benchmark-tau2-small = {
      repository       = "ansible-proxmox-ai"
      playbook         = "playbooks/benchmark-run.yml"
      limit            = "all"
      mutating         = true
      schedule_enabled = true
      rail_sec         = 3300
      extra_args = [
        "--extra-vars",
        "suite=tau2-banking-knowledge tau2_domain=airline tau2_max_concurrency=2 tau2_num_trials=1 concurrency=2 model=small tokenizer=Qwen/Qwen3.5-9B upgrade=false publish=false api_key_kv_path=apps/evals api_key_kv_field=evals_llm_router_key run_id=tau2-small-{{ now(utc=true, fmt='%Y%m%dT%H%M') }} node=${var.benchmark_client_node} client_vmid=${var.benchmark_client_vmid} gpu_guest_vmid=${var.benchmark_small_guest_vmid} engine_url=${var.benchmark_router_url}",
      ]
      description = "Run the tau2 airline suite hourly on the small lane."
    }
  }
}
