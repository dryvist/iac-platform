# Saturday converge templates for the apps and Proxmox layers. Scheduled in
# schedules.tf after the Saturday upgrade waves.

locals {
  ansible_templates_saturday_deploys = {
    apps-leantime = {
      repository       = "ansible-proxmox-apps"
      playbook         = "playbooks/site.yml"
      limit            = "leantime_group"
      mutating         = true
      schedule_enabled = true
      deployed_only    = true
      extra_args       = []
      rail_sec         = 2400
      description      = "Saturday Leantime converge, limited to leantime_group."
    }

    proxmox-oci-app-upgrade = {
      repository       = "ansible-proxmox"
      playbook         = "playbooks/oci_app_upgrade.yml"
      limit            = "proxmox"
      mutating         = true
      schedule_enabled = true
      extra_args       = []
      rail_sec         = 3600
      description      = "Saturday OCI app upgrade on the proxmox group."
    }
  }
}
