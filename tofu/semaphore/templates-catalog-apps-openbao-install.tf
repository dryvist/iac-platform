# The OpenBao package-install phase template, kept in its own file because
# templates-catalog-apps.tf is at the 12 KB File Size gate. See
# templates-catalog.tf for field docs.
locals {
  ansible_templates_apps_openbao_install = {
    apps-openbao-install = {
      repository       = "ansible-proxmox-apps"
      project          = "secrets"
      playbook         = "playbooks/site.yml"
      limit            = "openbao_group"
      tags             = "openbao_install"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "OpenBao package install phase only, via --tags openbao_install; pass --limit <member>,localhost to upgrade one store member."
    }
  }
}
