# The OpenBao KV seed phase template, kept in its own file because
# templates-catalog-apps.tf is at the 12 KB File Size gate. See
# templates-catalog.tf for field docs.
locals {
  ansible_templates_apps_openbao_kv_seed = {
    apps-openbao-kv-seed = {
      repository       = "ansible-proxmox-apps"
      project          = "secrets"
      playbook         = "playbooks/site.yml"
      limit            = "openbao_group"
      tags             = "openbao_kv_seed"
      mutating         = true
      schedule_enabled = false
      rail_sec         = 2400
      extra_args       = []
      description      = "OpenBao KV seed phase only, via --tags openbao_kv_seed (promoted and generated secret leaves, write-if-changed)."
    }
  }
}
