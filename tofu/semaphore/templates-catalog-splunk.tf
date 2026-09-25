# ansible-splunk templates. See templates-catalog.tf for field docs.

locals {
  ansible_templates_splunk = {
    splunk-site = {
      repository       = "ansible-splunk"
      project          = "observability"
      playbook         = "playbooks/site.yml"
      limit            = "all"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Full Splunk converge."
    }

    splunk-weekly-update = {
      repository       = "ansible-splunk"
      project          = "observability"
      playbook         = "playbooks/site.yml"
      limit            = "all"
      mutating         = true
      schedule_enabled = true
      extra_args       = ["--extra-vars", "splunkbase_sync_fail_open=false"]
      description      = "Thursday full Splunk converge with a fail-closed app update."
    }

    splunk-validate = {
      repository       = "ansible-splunk"
      project          = "observability"
      playbook         = "playbooks/validate.yml"
      limit            = "splunk"
      mutating         = false
      schedule_enabled = true
      extra_args       = []
      description      = "Read-only verification of the Splunk deployment."
    }
  }
}
