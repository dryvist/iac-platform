# The playbook catalog: one entry per playbook Semaphore may run.
# templates.tf turns these into resources; the header there explains the
# wrapper contract every entry rides on.

locals {
  # `limit` is the host pattern WITHOUT localhost; the argument list appends it,
  # so no entry here can forget it.
  #
  # `mutating` drives schedules.tf. It is not a comment — a template marked
  # false is eligible to run unattended, so it is the safety property of this
  # whole file and is asserted on below.
  #
  # `tags` is optional and omitted by almost every entry. Set it only when a
  # playbook must be run for some of its plays rather than in full, and only
  # after confirming each tag is carried by the play itself with a static
  # `roles:` list — `--tags` never reaches inside an untagged `include_role`,
  # and a tag that matches nothing yields a converge that runs cleanly, changes
  # nothing and reports success. A scoped entry still names the ENTRY playbook
  # (the one whose preamble loads the inventory), never an imported fragment
  # of it. A scoped entry is a second template, never an edit to the
  # full-scope one, so narrowing this file can never narrow what an existing
  # caller already gets.
  ansible_templates = {
    apps-site = {
      repository       = "ansible-proxmox-apps"
      playbook         = "playbooks/site.yml"
      limit            = "all"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Full application-layer converge."
    }

    apps-verify-grafana-dashboards = {
      repository       = "ansible-proxmox-apps"
      playbook         = "playbooks/verify-grafana-dashboards.yml"
      limit            = "grafana_group"
      mutating         = false
      schedule_enabled = true
      extra_args       = []
      description      = "Read-only check that provisioned dashboards are loaded."
    }

    apps-validate-pipeline = {
      repository = "ansible-proxmox-apps"
      playbook   = "playbooks/validate-pipeline.yml"
      limit      = "all"
      # Composed of many imported validate-pipeline/* playbooks. Declared so it
      # can be run on demand, but marked mutating because "every imported play
      # is read-only" has not been established for all of them, and an unproven
      # read-only claim is not a basis for running something unattended.
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Log-pipeline validation across HAProxy, Cribl Edge and Cribl Stream."
    }

    proxmox-site = {
      repository       = "ansible-proxmox"
      playbook         = "playbooks/site.yml"
      limit            = "all"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Full hypervisor-layer converge."
    }

    proxmox-validate-nas = {
      repository = "ansible-proxmox"
      playbook   = "playbooks/validate-nas.yml"
      limit      = "proxmox"
      # Asserts and reads, but reaches the hosts through ansible.builtin.command
      # whose effect is not verifiable from the module list alone. On demand
      # only until it is.
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Validation of the hypervisor SMB shares."
    }

    splunk-site = {
      repository       = "ansible-splunk"
      playbook         = "playbooks/site.yml"
      limit            = "all"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Full Splunk converge."
    }

    splunk-weekly-update = {
      repository       = "ansible-splunk"
      playbook         = "playbooks/site.yml"
      limit            = "all"
      mutating         = true
      schedule_enabled = true
      extra_args       = ["--extra-vars", "splunkbase_sync_fail_open=false"]
      description      = "Thursday full Splunk converge with a fail-closed app update."
    }

    splunk-validate = {
      repository       = "ansible-splunk"
      playbook         = "playbooks/validate.yml"
      limit            = "splunk"
      mutating         = false
      schedule_enabled = true
      extra_args       = []
      description      = "Read-only verification of the Splunk deployment."
    }

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

    # Two scoped second templates, never edits of apps-site: each narrows the
    # full-scope converge to one play-level tag on a static `include_role`, so
    # --tags reaches it cleanly (the constraint documented above).
    apps-zammad = {
      repository       = "ansible-proxmox-apps"
      playbook         = "playbooks/site.yml"
      limit            = "zammad_group"
      tags             = "zammad"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Zammad ITSM converge only (bootstrap seeds the incident closure-contract Job, SLA and overview), via --tags zammad."
    }

    # Declares the template that already exists on the plane as id 13
    # (undeclared drift) — see the import block in templates.tf.
    apps-openbao-tagged = {
      repository       = "ansible-proxmox-apps"
      playbook         = "playbooks/site.yml"
      limit            = "all"
      tags             = "openbao"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Store reconciliation only, via --tags openbao. Skips the baseline phase."
    }

    # The SSO portal play carries the `authelia` tag on a static `roles:` entry,
    # so --tags reaches it under the same constraint as the two above. The
    # secret pre-fetch play is tagged `always`, so a run scoped this way still
    # resolves the portal's own credentials rather than converging against an
    # empty secret domain.
    apps-authelia = {
      repository       = "ansible-proxmox-apps"
      playbook         = "playbooks/site.yml"
      limit            = "authelia_group"
      tags             = "authelia"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "SSO portal converge only, via --tags authelia. Skips the baseline phase."
    }
  }
}
