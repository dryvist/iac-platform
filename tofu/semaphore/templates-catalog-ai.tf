# ansible-proxmox-ai templates. See templates-catalog.tf for field docs.

locals {
  ansible_templates_ai = {
    ai-site = {
      repository  = "ansible-proxmox-ai"
      playbook    = "playbooks/site.yml"
      limit       = "all"
      mutating    = true
      description = "Full AI/LLM stack converge (Ollama, LiteLLM, Qdrant, Hermes, Langfuse, etc.)."
    }

    # Both scoped AI entries enter through site.yml, never through the
    # llm-serving.yml fragment they narrow to. That file is an import_playbook
    # fragment of site.yml: it carries neither the inventory loader nor the
    # always-tagged secrets pre-fetch, so run on its own it matches no hosts,
    # skips every play and reports success (the recap wrapper caught exactly
    # that). Entering through site.yml keeps both preamble plays, and the tags
    # select the fragment's plays from there.
    ai-llm-serving = {
      repository = "ansible-proxmox-ai"
      playbook   = "playbooks/site.yml"
      limit      = "all"
      # Exactly the four plays llm-serving.yml contains: the two llama.cpp
      # tiers, the spend store and the router. Not the broader `llm` tag —
      # in site.yml it also matches the Ollama and Open WebUI plays.
      tags        = "llama_cpp,llm_redis,llm_router"
      mutating    = true
      description = "GPU inference serving stack converge (llama.cpp, LiteLLM proxy, Redis spend store)."
    }

    ai-llm-profile = {
      repository = "ansible-proxmox-ai"
      playbook   = "playbooks/site.yml"
      limit      = "all"
      tags       = "llm_gpu_serving"
      mutating   = true
      survey_vars = [{
        name        = "llm_active_profile"
        title       = "profile"
        description = "Select the active LLM GPU serving profile."
        required    = true
        type        = "enum"
        enum_values = {
          small      = "small"
          "medium-a" = "medium-a"
          "medium-b" = "medium-b"
          max        = "max"
        }
      }]
      description = "Select and apply the active LLM GPU serving profile."
    }

    # The AI repository imports playbooks/llm-model-campaign.yml from site.yml
    # with the model_campaign tag; this template runs that tagged entry path.
    ai-llm-model-campaign = {
      repository       = "ansible-proxmox-ai"
      playbook         = "playbooks/site.yml"
      limit            = "all"
      tags             = "model_campaign"
      mutating         = true
      schedule_enabled = false
      survey_vars = [
        {
          name        = "config_name"
          title       = "Benchmark config"
          description = "Named TOML under configs/<tool>/; omit the .toml suffix."
          required    = true
          type        = "enum"
          enum_values = {
            "llama-cpp/cross-card"       = "llama-cpp/cross-card"
            "vllm/cross-card"            = "vllm/cross-card"
            "mlx/cross-card"             = "mlx/cross-card"
            "lm-eval/quick-intelligence" = "lm-eval/quick-intelligence"
          }
        },
        {
          name        = "machine"
          title       = "Machine selector"
          description = "Inventory-backed alias; do not enter a hostname or address."
          required    = true
          type        = "string"
        },
        {
          name        = "engine"
          title       = "Engine"
          description = "Engine selector supported by the chosen config."
          required    = true
          type        = "string"
        },
        {
          name        = "model_size"
          title       = "Model size"
          description = "AI registry size key; do not enter a model ID or quantization."
          required    = true
          type        = "string"
        },
        {
          name        = "concurrency_list"
          title       = "Concurrency list"
          description = "Comma-separated positive integers supported by the config."
          required    = true
          type        = "string"
        },
        {
          name        = "context_list"
          title       = "Context list"
          description = "Comma-separated positive prompt-token targets supported by the config."
          required    = true
          type        = "string"
        },
        {
          name        = "power_cap_w"
          title       = "Power cap (W)"
          description = "Positive watts, or 0 when no cap applies."
          required    = true
          type        = "string"
        },
      ]
      description = "Run a named LLM benchmark config with inventory and model-registry validated survey parameters."
    }

    ai-llm-router = {
      repository = "ansible-proxmox-ai"
      playbook   = "playbooks/site.yml"
      limit      = "llm_router_group"
      tags       = "llm_router"
      # The sibling above runs all four serving plays, reaching the ROCm tier,
      # the NVIDIA guest and the spend store as well as the router. This entry
      # exists so the router can be converged on its own without owning those
      # three outcomes.
      #
      # Mutating: the play restarts pool members. It does so one at a time
      # (`serial: 1`, `max_fail_percentage: 0`) so the front door stays up,
      # but a rolling restart is still a restart.
      mutating    = true
      description = "LiteLLM router converge only, scoped by tag and limit."
    }

    ai-llm-router-rebuild = {
      repository       = "ansible-proxmox-ai"
      playbook         = "playbooks/site.yml"
      limit            = "llm_router_group"
      tags             = "llm_router"
      mutating         = true
      schedule_enabled = false
      extra_args       = ["--extra-vars", "llm_router_seed_mode=rebuild"]
      description      = "LiteLLM router converge with llm_router_seed_mode=rebuild: re-seeds roles, fallbacks and router_settings from git."
    }

    # diff = false: the role syncs a full source tree, and its --diff output
    # is too large to store as task output.
    ai-hermes-agent = {
      repository  = "ansible-proxmox-ai"
      playbook    = "playbooks/site.yml"
      limit       = "hermes_agent_group"
      tags        = "hermes_agent"
      mutating    = true
      diff        = false
      description = "Hermes Agent (and companion identities) converge only, scoped by tag and limit."
    }
  }
}
