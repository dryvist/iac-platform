# Further ansible-proxmox-apps site.yml splits, kept in their own file
# because templates-catalog-apps.tf hit the 12KB File Size gate. See
# templates-catalog-apps.tf for field docs and the pattern these follow
# (apps-cribl/apps-cribl-stream, apps-grafana, apps-zammad, ...).
#
# Covers the plays that had no --tags entry point yet (Vikunja 3476): 01's
# apt-proxy/apt-cacher/Zot/syslog-forwarder/RustFS/PBS, 02's DNS/HAProxy/
# netmon/exporters, 03 in full, 04's remaining collab apps, and 05's media
# stack. Each template reuses the role's own existing per-play tags — no
# ansible-proxmox-apps role changes.

locals {
  ansible_templates_apps_site_split = {
    # The LXC-side half of site/01-baseline-infra.yml's "Configure apt proxy
    # on LXC containers and docker VMs" play (measured 6m20s combined across
    # both host groups — the single biggest chunk in task 328's profile).
    # Splitting the play by host group between this template and
    # apps-docker-apt-proxy below keeps each half under budget without
    # touching ansible.cfg/strategy. Also picks up the other single-group
    # LXC plays in 01 that have no template of their own.
    apps-baseline-lxc = {
      repository       = "ansible-proxmox-apps"
      playbook         = "playbooks/site.yml"
      limit            = "lxc_containers,apt_cacher_group,registry_group,object_storage_group,pbs_group"
      tags             = "baseline,apt_proxy,apt_cacher_ng,zot,syslog_forwarder,object-storage,pbs"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "LXC-side baseline converge (apt cache/proxy, Zot, syslog forwarder, RustFS, PBS, ssh_ca_trust/ntp/node_exporter/cadvisor on LXCs), via --tags baseline,apt_proxy,apt_cacher_ng,zot,syslog_forwarder,object-storage,pbs."
    }

    # The docker_vms-side half of the same apt-proxy play, plus 01a's Docker
    # registry mirror play (also lxc_containers:docker_vms). apps-baseline-
    # docker-vms (templates-catalog-apps.tf) already covers docker_vms's
    # baseline tag (ssh_ca_trust/ntp/node_exporter/cadvisor); this covers the
    # rest of that host group's baseline-phase work.
    apps-docker-apt-proxy = {
      repository       = "ansible-proxmox-apps"
      playbook         = "playbooks/site.yml"
      limit            = "docker_vms"
      tags             = "apt_proxy,registry_mirror"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Docker VM apt proxy and registry mirror converge only, via --tags apt_proxy,registry_mirror."
    }

    # site/02-dns-and-pipeline.yml, minus cribl/cribl_stream/prometheus which
    # already have their own scoped templates in templates-catalog-apps.tf.
    apps-dns-pipeline = {
      repository       = "ansible-proxmox-apps"
      playbook         = "playbooks/site.yml"
      limit            = "technitium_dns_group,haproxy_group,netmon_group,prometheus_group,unifi_metrics_group"
      tags             = "technitium_install,technitium_dns,haproxy,netmon,smokeping,prometheus_pve_exporter,github_exporter,unifi_metrics"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "DNS and syslog/netflow pipeline converge (Technitium, HAProxy, netmon, exporters), via --tags technitium_install,technitium_dns,haproxy,netmon,smokeping,prometheus_pve_exporter,github_exporter,unifi_metrics."
    }

    # site/03-notifications-and-core-apps.yml in full — no play in this file
    # has its own template yet.
    apps-core-apps = {
      repository       = "ansible-proxmox-apps"
      playbook         = "playbooks/site.yml"
      limit            = "mailpit_group,ntfy_group,healthchecks_group,technitium_dns_group,traefik_group,haproxy_group,openbao_group,docker_vms,mssql_group,postgres_group,postgres_ai_group,nautobot_group,idrac_kvm_group,n8n_group,openproject_group"
      tags             = "mailpit,ntfy,healthchecks,service_deadman,mssql_docker,postgres,postgres_ai,nautobot,agent_sandbox,opentofu_cli,idrac_kvm_docker,n8n_docker,openproject_docker"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Notifications and core apps converge (mailpit, ntfy, healthchecks, deadman, mssql, postgres, nautobot, n8n, openproject, ...), via --tags mailpit,ntfy,healthchecks,service_deadman,mssql_docker,postgres,postgres_ai,nautobot,agent_sandbox,opentofu_cli,idrac_kvm_docker,n8n_docker,openproject_docker."
    }

    # site/04-secrets-and-collab-apps.yml, minus openbao (apps-openbao-tagged),
    # zammad, vikunja, authelia and grafana, which already have their own
    # scoped templates in templates-catalog-apps.tf.
    apps-collab = {
      repository       = "ansible-proxmox-apps"
      playbook         = "playbooks/site.yml"
      limit            = "immich_group,homeassistant_group,phpipam_group,homarr_group,homepage_group,glance_group,status_group,traefik_group"
      tags             = "immich,homeassistant,phpipam,homarr,homepage,glance,status,traefik"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Remaining collaboration apps converge (immich, homeassistant, phpipam, homarr, homepage, glance, status, traefik), via --tags immich,homeassistant,phpipam,homarr,homepage,glance,status,traefik."
    }

    # site/05-media-and-gate.yml. site/04b-github-runners.yml's own play is
    # already covered by apps-github-runner (templates-catalog-apps.tf), so
    # only the `media` tag is needed here.
    apps-media = {
      repository       = "ansible-proxmox-apps"
      playbook         = "playbooks/site.yml"
      limit            = "media_group"
      tags             = "media"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Media stack converge only, via --tags media."
    }

    # site/04's Traefik ingress play alone. apps-collab also carries it, but
    # runs it last, after every collab app.
    apps-traefik = {
      repository       = "ansible-proxmox-apps"
      playbook         = "playbooks/site.yml"
      limit            = "traefik_group"
      tags             = "traefik"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Traefik ingress converge only, via --tags traefik."
    }

    # site/04c-wall.yml: the server-room wall pages and data gateway.
    apps-wall = {
      repository       = "ansible-proxmox-apps"
      playbook         = "playbooks/site.yml"
      limit            = "wall_group"
      tags             = "wall"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Server-room wall converge only, via --tags wall."
    }
  }
}
