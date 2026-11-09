# The Hermes Agent entries, kept in their own file because
# templates-catalog-ai.tf is at the 12KB File Size gate. Entries here follow
# the field docs in templates-catalog.tf and the shape of the sibling entries
# in templates-catalog-ai.tf.

locals {
  ansible_templates_ai_hermes = {
    # diff = false: the role syncs a full source tree, and its --diff output
    # is too large to store as task output. The 2400-second rail: a full converge
    # of the Hermes identities runs past the 900-second default.
    ai-hermes-agent = {
      repository  = "ansible-proxmox-ai"
      playbook    = "playbooks/site.yml"
      limit       = "hermes_agent_group"
      tags        = "hermes_agent"
      mutating    = true
      diff        = false
      rail_sec    = 2400
      description = "Hermes Agent (and companion identities) converge only, scoped by tag and limit."
    }

    # Ansible unions repeated --tags, so the hermes_crons component cannot be
    # selected by adding a tag to ai-hermes-agent: it needs its own template.
    # diff = false for the same reason as ai-hermes-agent; the 540-second rail
    # fits the 10-minute component rule.
    ai-hermes-crons = {
      repository       = "ansible-proxmox-ai"
      playbook         = "playbooks/site.yml"
      limit            = "hermes_agent_group"
      tags             = "hermes_crons"
      mutating         = true
      schedule_enabled = false
      diff             = false
      rail_sec         = 540
      description      = "Hermes cron reconcile only: prompt catalog, pre-reconcile checks and the cron fleet."
    }
  }
}
