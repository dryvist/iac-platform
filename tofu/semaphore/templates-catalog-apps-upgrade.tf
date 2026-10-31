# The weekly Debian guest OS upgrade, split into per-wave templates so each run
# fits its 3000-second rail. Every entry runs playbooks/upgrade.yml from
# ansible-proxmox-apps with its own limit. apps-upgrade (templates-catalog-apps.tf)
# is wave 0. The LXC waves are the inventory groups upgrade_wave_<n>; lxc-rest
# takes every other LXC container, and vms takes the VM groups. See
# templates-catalog.tf for field docs.
#
# Limits are comma lists with `!` exclusions. A colon is not split by the
# wrapper, so it never appears here. Crons run Saturdays 06:45 to 06:51 UTC
# (schedules.tf). deployed_only builds no `@ <branch>` twin of these entries.

locals {
  ansible_templates_apps_upgrade = {
    apps-upgrade-lxc-1 = {
      repository       = "ansible-proxmox-apps"
      playbook         = "playbooks/upgrade.yml"
      limit            = "upgrade_wave_1"
      mutating         = true
      schedule_enabled = true
      deployed_only    = true
      extra_args       = []
      rail_sec         = 3000
      description      = "Weekly Debian guest OS upgrade, LXC wave 1 only (upgrade_wave_1)."
    }

    apps-upgrade-lxc-2 = {
      repository       = "ansible-proxmox-apps"
      playbook         = "playbooks/upgrade.yml"
      limit            = "upgrade_wave_2"
      mutating         = true
      schedule_enabled = true
      deployed_only    = true
      extra_args       = []
      rail_sec         = 3000
      description      = "Weekly Debian guest OS upgrade, LXC wave 2 only (upgrade_wave_2)."
    }

    apps-upgrade-lxc-3 = {
      repository       = "ansible-proxmox-apps"
      playbook         = "playbooks/upgrade.yml"
      limit            = "upgrade_wave_3"
      mutating         = true
      schedule_enabled = true
      deployed_only    = true
      extra_args       = []
      rail_sec         = 3000
      description      = "Weekly Debian guest OS upgrade, LXC wave 3 only (upgrade_wave_3)."
    }

    apps-upgrade-lxc-rest = {
      repository       = "ansible-proxmox-apps"
      playbook         = "playbooks/upgrade.yml"
      limit            = "lxc_containers,!upgrade_wave_0,!upgrade_wave_1,!upgrade_wave_2,!upgrade_wave_3"
      mutating         = true
      schedule_enabled = true
      deployed_only    = true
      extra_args       = []
      rail_sec         = 3000
      description      = "Weekly Debian guest OS upgrade, LXC containers outside waves 0 to 3."
    }

    apps-upgrade-vms = {
      repository       = "ansible-proxmox-apps"
      playbook         = "playbooks/upgrade.yml"
      limit            = "vms,docker_vms,splunk_vms"
      mutating         = true
      schedule_enabled = true
      deployed_only    = true
      extra_args       = []
      rail_sec         = 3000
      description      = "Weekly Debian guest OS upgrade, VM groups only (vms, docker_vms, splunk_vms)."
    }
  }
}
