# ansible-splunk templates. See templates-catalog.tf for field docs.

locals {
  ansible_templates_splunk = {
    splunk-site = {
      repository       = "ansible-splunk"
      playbook         = "playbooks/site.yml"
      limit            = "all"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      rail_sec         = 3600
      description      = "Full Splunk converge, with the 60-minute task allowance."
    }

    splunk-weekly-update = {
      repository       = "ansible-splunk"
      playbook         = "playbooks/site.yml"
      limit            = "all"
      mutating         = true
      schedule_enabled = true
      extra_args       = ["--extra-vars", "splunkbase_sync_fail_open=false"]
      description      = "Saturday full Splunk converge with a fail-closed app update."
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

    # Forces a container restart after a bypassed install path; the site
    # converge only restarts on a reported change.
    splunk-restart = {
      repository       = "ansible-splunk"
      playbook         = "playbooks/restart-splunk.yml"
      limit            = "splunk"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Restart the Splunk container and wait for the management port."
    }

    # Standalone search head: native install, then licence manager. Runs the
    # playbook untagged on purpose: the role includes its task files
    # dynamically, so --tags would skip them. The search-peer play is tagged
    # `never` and stays out of this run.
    splunk-search-head = {
      repository       = "ansible-splunk"
      playbook         = "playbooks/deploy-search-head.yml"
      limit            = "splunk_sh"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Install Splunk on the standalone search head and make it the licence manager."
    }
  }
}
