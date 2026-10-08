# ansible-proxmox templates. See templates-catalog.tf for field docs.

locals {
  ansible_templates_proxmox = {
    proxmox-site = {
      repository       = "ansible-proxmox"
      playbook         = "playbooks/site.yml"
      limit            = "all"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Full hypervisor-layer converge."
    }

    proxmox-validate-nas = {
      repository = "ansible-proxmox"
      playbook   = "playbooks/validate-nas.yml"
      limit      = "proxmox"
      # Asserts and reads, but reaches the hosts through ansible.builtin.command
      # whose effect is not verifiable from the module list alone. On demand
      # only until it is.
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Validation of the hypervisor SMB shares."
    }

    # playbooks/node-hardware.yml's idrac_kiosk role only; inert on hosts that
    # do not opt in.
    proxmox-idrac-kiosk = {
      repository       = "ansible-proxmox"
      playbook         = "playbooks/site.yml"
      limit            = "proxmox"
      tags             = "idrac_kiosk"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Node console kiosk converge only, via --tags idrac_kiosk."
    }

    # docker_lxc_features only: the root-only nesting/keyctl/fuse flags every
    # docker-tagged LXC needs for Docker's fuse-overlayfs storage driver.
    proxmox-docker-lxc-features = {
      repository       = "ansible-proxmox"
      playbook         = "playbooks/site.yml"
      limit            = "proxmox"
      tags             = "docker_lxc_features"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "Docker-in-LXC feature flags only, via --tags docker_lxc_features."
    }

    # pve_node_exporter only: node_exporter version/flag changes (e.g. the
    # drm collector) without a full hypervisor-layer converge.
    proxmox-node-exporter = {
      repository       = "ansible-proxmox"
      playbook         = "playbooks/site.yml"
      limit            = "proxmox"
      tags             = "pve_node_exporter"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      description      = "node_exporter converge only, via --tags pve_node_exporter."
    }

    # One power action on one guest by VMID; the node is read from live
    # placement by the playbook. Entry is guest-power.yml, which needs no tag.
    proxmox-guest-power = {
      repository       = "ansible-proxmox"
      playbook         = "playbooks/guest-power.yml"
      limit            = "proxmox"
      mutating         = true
      schedule_enabled = false
      survey_vars = [
        {
          name        = "guest_power_vmid"
          title       = "Guest VMID"
          description = "Numeric VMID of the guest to act on."
          required    = true
          type        = "string"
        },
        {
          name        = "guest_power_type"
          title       = "Guest type"
          description = "Guest kind: qemu or lxc."
          required    = true
          type        = "enum"
          enum_values = {
            qemu = "qemu"
            lxc  = "lxc"
          }
        },
        {
          name        = "guest_power_action"
          title       = "Power action"
          description = "Action to run; reset applies to qemu only."
          required    = true
          type        = "enum"
          enum_values = {
            start    = "start"
            stop     = "stop"
            shutdown = "shutdown"
            reboot   = "reboot"
            reset    = "reset"
          }
        },
      ]
      description = "Power action (start, stop, shutdown, reboot, reset) on one guest by VMID, on the node that hosts it."
    }
  }
}
