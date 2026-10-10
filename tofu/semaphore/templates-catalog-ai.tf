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

    # The develop-to-main promotion check: the same converge as ai-site, run
    # from the develop ref only (only_branch builds no deployed-ref variant), with the
    # 3600-second allowance. rail_sec puts --rail-sec first in the arguments,
    # the one position the wrapper honours; a task override is appended after
    # the arguments and cannot reach it. The contract test in
    # tests/promotion_rail_contract.tftest.hcl lists every entry allowed a
    # rail_sec and its value.
    ai-site-promotion = {
      repository  = "ansible-proxmox-ai"
      playbook    = "playbooks/site.yml"
      limit       = "all"
      mutating    = true
      only_branch = "develop"
      rail_sec    = 3600
      description = "Promotion validation: full AI/LLM stack converge from develop, with the 60-minute task allowance."
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

    # The profile switch converges both halves: the serving role starts the
    # selected profile's unit on the GPU guest, and the router re-projects the
    # active profile's deployment. Entry is site.yml for the same reason as the
    # entries above: the inventory loader and the always-tagged secrets
    # pre-fetch live there. The limit names both groups; localhost is appended.
    ai-llm-profile = {
      repository = "ansible-proxmox-ai"
      playbook   = "playbooks/site.yml"
      limit      = "llm_gpu_group,llm_router_group"
      tags       = "llm_gpu_serving,llm_router"
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
      description = "Select the active LLM GPU serving profile and converge the serving role and the router for it."
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
            "lm-eval/gpqa-diamond"       = "lm-eval/gpqa-diamond"
            "evalscope/livecodebench"    = "evalscope/livecodebench"
          }
        },
        {
          name        = "machine"
          title       = "Benchmark target inventory alias"
          description = "Benchmark target inventory alias."
          required    = true
          type        = "string"
        },
        {
          name        = "benchmark_endpoint_root"
          title       = "Serving endpoint origin"
          description = "HTTPS FQDN origin declared for the selected target; no path or address."
          required    = true
          type        = "string"
        },
        {
          name        = "benchmark_cache_path"
          title       = "Model cache path"
          description = "Existing target-local writable cache directory from its inventory."
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
      description = "Run a named LLM benchmark config with target inventory and model-registry validated parameters."
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
    # is too large to store as task output. The 1800-second rail: a full converge
    # of the Hermes identities runs past the 900-second default.
    ai-hermes-agent = {
      repository  = "ansible-proxmox-ai"
      playbook    = "playbooks/site.yml"
      limit       = "hermes_agent_group"
      tags        = "hermes_agent"
      mutating    = true
      diff        = false
      rail_sec    = 1800
      description = "Hermes Agent (and companion identities) converge only, scoped by tag and limit."
    }
  }
}
