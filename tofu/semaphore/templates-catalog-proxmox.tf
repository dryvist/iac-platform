# ansible-proxmox templates. See templates-catalog.tf for field docs.

locals {
  ansible_templates_proxmox = {
    # The 3600-second rail: a full hypervisor converge seeds model-store blobs
    # and runs past the 900-second default.
    proxmox-site = {
      repository       = "ansible-proxmox"
      playbook         = "playbooks/site.yml"
      limit            = "all"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      rail_sec         = 3600
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

    proxmox-preflight-gate = {
      repository       = "ansible-proxmox"
      playbook         = "playbooks/preflight_gate.yml"
      limit            = "proxmox"
      mutating         = false
      schedule_enabled = false
      extra_args       = []
      description      = "Read-only Nautobot capacity and storage pre-flight plus HA relocation admission check."
    }

    proxmox-preflight-gate-selftest = {
      repository       = "ansible-proxmox"
      playbook         = "tests/preflight_gate/verify.yml"
      limit            = "proxmox"
      mutating         = false
      schedule_enabled = false
      extra_args       = []
      description      = "Offline fixtures that prove the pre-flight gate rejects over-committed memory, a wrong or missing storage pool and an unsafe HA recovery node."
    }

    proxmox-access-verification = {
      repository       = "ansible-proxmox"
      playbook         = "tests/access_verification/verify.yml"
      limit            = "proxmox"
      mutating         = false
      schedule_enabled = false
      extra_args       = []
      description      = "Verify SSH certificate access and report pending service identity probes."
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

    proxmox-fan-control = {
      repository       = "ansible-proxmox"
      playbook         = "playbooks/site.yml"
      limit            = "proxmox"
      tags             = "fan_control"
      mutating         = true
      schedule_enabled = false
      extra_args       = ["--extra-vars", "fan_control=true fan_control_active_mode=benchmark-100"]
      only_branch      = "develop"
      description      = "Apply benchmark-100 fan-control settings only, via --tags fan_control."
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

    proxmox-guest-recovery = {
      repository       = "ansible-proxmox"
      playbook         = "playbooks/guest-recovery.yml"
      limit            = "proxmox"
      mutating         = true
      schedule_enabled = false
      extra_args       = []
      survey_vars = [
        {
          name        = "node"
          title       = "Node"
          description = "Inventory host name from the proxmox group."
          required    = true
          type        = "string"
        },
        {
          name        = "vmid"
          title       = "VMID"
          description = "Numeric VMID of the guest to recover."
          required    = true
          type        = "string"
        },
        {
          name        = "mode"
          title       = "Recovery mode"
          description = "Select a service-unit action or a guest restart."
          required    = true
          type        = "enum"
          enum_values = {
            unit-stop     = "unit-stop"
            unit-kill     = "unit-kill"
            guest-restart = "guest-restart"
          }
        },
        {
          name        = "unit"
          title       = "Service unit"
          description = "Required for unit-stop and unit-kill; include the .service suffix."
          required    = false
          type        = "string"
        },
        {
          name        = "reason"
          title       = "Reason"
          description = "Required and included in the task output."
          required    = true
          type        = "string"
        },
        {
          name        = "memory_headroom_mb"
          title       = "Temporary memory headroom (MB)"
          description = "Optional positive headroom for unit-kill; the original setting is restored."
          required    = false
          type        = "string"
        },
      ]
      description = "Run a bounded unit stop, unit cgroup kill, or guest restart on one selected inventory node."
    }
  }
}
