# ansible-proxmox-ai templates. See templates-catalog.tf for field docs.

locals {
  ansible_templates_ai = {
    ai-site = {
      repository  = "ansible-proxmox-ai"
      project     = "ai"
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
      project    = "ai"
      playbook   = "playbooks/site.yml"
      limit      = "all"
      # Exactly the four plays llm-serving.yml contains: the two llama.cpp
      # tiers, the spend store and the router. Not the broader `llm` tag —
      # in site.yml it also matches the Ollama and Open WebUI plays.
      tags        = "llama_cpp,llm_redis,llm_router"
      mutating    = true
      description = "GPU inference serving stack converge (llama.cpp, LiteLLM proxy, Redis spend store)."
    }

    ai-llm-router = {
      repository = "ansible-proxmox-ai"
      project    = "ai"
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
  }
}
