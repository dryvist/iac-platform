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
  }
}
