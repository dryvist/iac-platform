# ansible-proxmox-apps templates. See templates-catalog.tf for field docs.

locals {
  ansible_templates_apps = {
    apps-site = {
      repository       = "ansible-proxmox-apps"
      project          = "apps"
      playbook         = "playbooks/site.yml"
      limit            = "all"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      # The full converge is the post-merge apply of the deployed ref and
      # nothing else; the scoped templates below cover preview testing.
      deployed_only = true
      description   = "Full application-layer converge."
    }

    apps-verify-grafana-dashboards = {
      repository       = "ansible-proxmox-apps"
      project          = "apps"
      playbook         = "playbooks/verify-grafana-dashboards.yml"
      limit            = "grafana_group"
      mutating         = false
      schedule_enabled = true
      extra_args       = []
      description      = "Read-only check that provisioned dashboards are loaded."
    }

    apps-validate-pipeline = {
      repository = "ansible-proxmox-apps"
      project    = "apps"
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

    # Two scoped second templates, never edits of apps-site: each narrows the
    # full-scope converge to one play-level tag on a static `include_role`, so
    # --tags reaches it cleanly (the constraint documented above).
    apps-zammad = {
      repository       = "ansible-proxmox-apps"
      project          = "apps"
      playbook         = "playbooks/site.yml"
      limit            = "zammad_group"
      tags             = "zammad"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Zammad ITSM converge only (bootstrap seeds the incident closure-contract Job, SLA and overview), via --tags zammad."
    }

    apps-vikunja = {
      repository       = "ansible-proxmox-apps"
      playbook         = "playbooks/site.yml"
      limit            = "vikunja_group"
      tags             = "vikunja"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Vikunja converge only, via --tags vikunja."
    }

    # Declares the template that already exists on the plane as id 13
    # (undeclared drift) — see the import block in templates.tf.
    apps-openbao-tagged = {
      repository = "ansible-proxmox-apps"
      # Privileged: reconciles OpenBao's own policies/AppRoles/secret_ids.
      # Its own project (never the shared "apps" one) so its per-project
      # max_parallel_tasks = 1 bounds only OTHER openbao-tagged runs against
      # each other — see tofu/semaphore/project.tf.
      project          = "secrets"
      playbook         = "playbooks/site.yml"
      limit            = "all"
      tags             = "openbao"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Store reconciliation only, via --tags openbao. Skips the baseline phase."
    }

    # The log/telemetry pipeline hosts. The `cribl` tag covers all three plays
    # that make up the pipeline — Stream, Edge and the shared packs — each on a
    # static `roles:` list, so --tags reaches them under the constraint
    # documented above. The limit names both groups because the packs play
    # spans them.
    #
    # Declared because the full-scope template is the only other route to these
    # hosts and it measures ~98 minutes, which the converge budget forbids. A
    # scoped run reaches them in minutes.
    apps-cribl = {
      repository = "ansible-proxmox-apps"
      project    = "apps"
      playbook   = "playbooks/site.yml"
      # COMMA, never a colon. A play's own `hosts:` accepts `a:b` as a union,
      # but --limit does not split on it: the whole string is taken as one
      # literal host name, matches nothing, and is dropped with a warning,
      # leaving only the appended localhost. The run then completes green over
      # a single host and changes nothing. Measured as task 205 — "Could not
      # match supplied host pattern, ignoring: cribl_edge:cribl_stream_group",
      # then a recap covering localhost alone. Single-group limits are fine,
      # which is why the grafana verifier's has always worked.
      limit            = "cribl_edge,cribl_stream_group"
      tags             = "cribl"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Log/telemetry pipeline converge only (Stream, Edge, packs), via --tags cribl."
    }

    # The Stream half of apps-cribl on its own. Both halves together run past
    # the per-run wall-clock budget, so there is no route to a completed Stream
    # converge through the combined entry. Splitting the two is what keeps each
    # one inside the budget; run this when only the Stream tier needs to move.
    apps-cribl-stream = {
      repository       = "ansible-proxmox-apps"
      project          = "apps"
      playbook         = "playbooks/site.yml"
      limit            = "cribl_stream_group"
      tags             = "cribl_stream"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Pipeline Stream tier converge only, via --tags cribl_stream."
    }

    # Grafana + VictoriaMetrics observability stack only. The full apps-site
    # converge takes far longer than a scoped run needs for this one stack;
    # this reaches grafana_group in minutes via the role's own play tag.
    apps-grafana = {
      repository       = "ansible-proxmox-apps"
      project          = "apps"
      playbook         = "playbooks/site.yml"
      limit            = "grafana_group"
      tags             = "grafana"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Grafana/VictoriaMetrics stack converge only, via --tags grafana."
    }

    # Authelia SSO portal only. Same scoping rationale as apps-grafana: reaches
    # authelia_group in minutes via the role's own play tag instead of the
    # full apps-site converge.
    apps-authelia = {
      repository       = "ansible-proxmox-apps"
      project          = "apps"
      playbook         = "playbooks/site.yml"
      limit            = "authelia_group"
      tags             = "authelia"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "SSO gateway converge only, via --tags authelia."
    }

    # Prometheus-native network monitoring stack only. Same scoping rationale
    # as apps-grafana: reaches prometheus_group in minutes via the role's own
    # play tag instead of the full apps-site converge.
    apps-prometheus = {
      repository       = "ansible-proxmox-apps"
      project          = "apps"
      playbook         = "playbooks/site.yml"
      limit            = "prometheus_group"
      tags             = "prometheus"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Prometheus-native monitoring converge only, via --tags prometheus."
    }

    # Runner hosts only. Same argument as apps-cribl: the full-scope template is
    # the only other route to them, and it now exceeds the run budget before it
    # gets there, so those hosts are unreachable in practice.
    apps-github-runner = {
      repository       = "ansible-proxmox-apps"
      project          = "apps"
      playbook         = "playbooks/site.yml"
      limit            = "docker_vms"
      tags             = "github_runner"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Runner host converge only, via --tags github_runner."
    }

    # Docker VM group only. Same argument as apps-github-runner: the
    # full-scope template is the only other route to the baseline plays
    # (ssh_ca_trust among them) and it now exceeds the run budget before it
    # gets there, so a VM that missed baseline once has no scoped path back
    # to it. `baseline` also carries ntp, node_exporter and cadvisor for this
    # host group — all lightweight (no apt installs beyond ntp's single
    # chrony package, everything else a binary/container fetch), so the set
    # stays well inside the run budget on three hosts.
    # Docker VM group only. `baseline` also carries ntp, node_exporter and
    # cadvisor for this host group. See templates-catalog-apps-site-split.tf
    # for the apt_proxy/registry_mirror split of this same play by host group.
    apps-baseline-docker-vms = {
      repository       = "ansible-proxmox-apps"
      project          = "apps"
      playbook         = "playbooks/site.yml"
      limit            = "docker_vms"
      tags             = "baseline"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Docker VM baseline converge only (ssh_ca_trust, ntp, node_exporter, cadvisor), via --tags baseline."
    }
  }
}
