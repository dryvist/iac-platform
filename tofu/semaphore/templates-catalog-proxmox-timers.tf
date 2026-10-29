# Proxmox timer-oriented templates. Split from the main Proxmox catalog to
# keep that file below the repository's 12 KB size gate.

locals {
  ansible_templates_proxmox_timers = {
    proxmox-config-backup = {
      repository       = "ansible-proxmox"
      playbook         = "playbooks/site.yml"
      limit            = "proxmox"
      tags             = "pve_config_backup"
      mutating         = true
      schedule_enabled = false
      only_branch      = "develop"
      description      = "Proxmox configuration backup only, via --tags pve_config_backup."
    }

    proxmox-postgres-standby = {
      repository       = "ansible-proxmox"
      playbook         = "playbooks/site.yml"
      limit            = "proxmox"
      tags             = "postgres_standby"
      mutating         = true
      schedule_enabled = false
      only_branch      = "develop"
      description      = "PostgreSQL standby timer management only, via --tags postgres_standby."
    }

    proxmox-backup-jobs = {
      repository       = "ansible-proxmox"
      playbook         = "playbooks/site.yml"
      limit            = "proxmox"
      tags             = "pve_backup_jobs"
      mutating         = true
      schedule_enabled = false
      only_branch      = "develop"
      description      = "Proxmox backup jobs only, via --tags pve_backup_jobs."
    }

    proxmox-zfs-scrub-window = {
      repository       = "ansible-proxmox"
      playbook         = "playbooks/site.yml"
      limit            = "proxmox"
      tags             = "zfs_scrub_window"
      mutating         = true
      schedule_enabled = false
      only_branch      = "develop"
      description      = "ZFS scrub window timers only, via --tags zfs_scrub_window."
    }
  }
}
