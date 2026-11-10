# Model-trial ansible-proxmox-ai templates: the GPU container runtime converge
# and the bounded model trial.

locals {
  ansible_templates_ai_trial = {
    # Each playbook imports its inventory loader. The container runtime converge
    # names the one trial guest in both the limit and the playbook's host variable.
    ai-llm-gpu-container-trial = {
      repository       = "ansible-proxmox-ai"
      playbook         = "playbooks/llm-gpu-container-trial.yml"
      limit            = "llm-blackwell-7-96GB-small"
      only_branch      = "develop"
      mutating         = true
      schedule_enabled = false
      rail_sec         = 1800
      extra_args       = ["llm_gpu_container_trial_hosts=llm-blackwell-7-96GB-small"]
      description      = "Install the GPU container runtime on the trial guest."
    }

    # One bounded model trial: the live GPU guest (baseline) plus the trial guest
    # (candidate). Candidate inputs arrive as task extra-vars.
    ai-llm-model-trial = {
      repository       = "ansible-proxmox-ai"
      playbook         = "playbooks/llm-model-trial.yml"
      limit            = "llm_gpu_group,llm-blackwell-7-96GB-small"
      only_branch      = "develop"
      mutating         = true
      schedule_enabled = false
      rail_sec         = 3600
      description      = "Run one bounded model trial with baseline restore."
    }
  }
}
