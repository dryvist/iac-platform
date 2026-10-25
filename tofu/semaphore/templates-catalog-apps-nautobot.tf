# The nightly Nautobot database backup, kept in its own file because
# templates-catalog-apps-site-split.tf is at the 12 KB File Size gate. See
# templates-catalog.tf for field docs.
#
# The play and the role's server and Jobs parts all carry the `nautobot` tag, and
# task arguments only add to a template's own, so this entry carries its
# narrowing itself: the stored --tags keeps the play selected and the skip tags
# leave only the role's untagged guards and the nautobot_backup part (the role
# README and tasks/main.yml describe the split).
locals {
  ansible_templates_apps_nautobot = {
    apps-nautobot-backup = {
      repository       = "ansible-proxmox-apps"
      playbook         = "playbooks/site.yml"
      limit            = "nautobot_group"
      tags             = "nautobot"
      mutating         = true
      schedule_enabled = false
      extra_args       = ["--skip-tags", "nautobot_server,nautobot_jobs"]
      description      = "Nautobot nightly database backup units only (restic to Backblaze B2), via --tags nautobot --skip-tags nautobot_server,nautobot_jobs."
    }
  }
}
