# The OpenHands host converge, kept in its own file because
# templates-catalog-apps-site-split.tf is at the 12 KB File Size gate. See
# templates-catalog.tf for field docs.
locals {
  ansible_templates_apps_openhands = {
    apps-openhands = {
      repository       = "ansible-proxmox-apps"
      playbook         = "playbooks/site.yml"
      limit            = "openhands_host"
      tags             = "apt_proxy,node_exporter,syslog_forwarder,openhands"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      rail_sec         = 1800
      description      = "OpenHands host converge only (apt proxy, node_exporter, log forwarding, OpenHands), via --tags apt_proxy,node_exporter,syslog_forwarder,openhands."
    }
  }
}
