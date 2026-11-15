# The scheduled ssh_ca_trust template, kept in its own file because
# templates-catalog-proxmox.tf is at the 12 KB File Size gate. See
# templates-catalog.tf for field docs.

locals {
  ansible_templates_proxmox_ssh_ca = {
    proxmox-ssh-ca-trust = {
      repository       = "ansible-proxmox"
      playbook         = "playbooks/site.yml"
      limit            = "proxmox"
      tags             = "ssh_ca_trust"
      mutating         = true
      schedule_enabled = true
      extra_args       = []
      rail_sec         = 1800
      description      = "SSH CA trust and LXC host certificates only, via --tags ssh_ca_trust."
    }
  }
}
