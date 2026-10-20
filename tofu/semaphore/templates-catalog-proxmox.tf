# ansible-proxmox templates. See templates-catalog.tf for field docs.

locals {
  ansible_templates_proxmox = {
    proxmox-upgrade = {
      repository       = "ansible-proxmox"
      playbook         = "playbooks/upgrade.yml"
      limit            = "proxmox"
      mutating         = true
      schedule_enabled = true
      extra_args       = []
      rail_sec         = 3600
      survey_vars = [
        {
          name        = "upgrade_nodes"
          title       = "Nodes to upgrade"
          description = "Node name(s) to upgrade; blank defaults to all Proxmox nodes."
          required    = false
          type        = "string"
        },
      ]
      description = "Monthly rolling Proxmox node upgrade with quorum checks; first Saturday only."
    }

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
    # placement by the playbook. startall and stopall act on one node instead,
    # from guest_power_node. Entry is guest-power.yml, which needs no tag.
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
          description = "Numeric VMID of the guest to act on. Guest actions only."
          required    = false
          type        = "string"
        },
        {
          name        = "guest_power_type"
          title       = "Guest type"
          description = "Guest kind: qemu or lxc. Guest actions only."
          required    = false
          type        = "enum"
          enum_values = {
            qemu = "qemu"
            lxc  = "lxc"
          }
        },
        {
          name        = "guest_power_action"
          title       = "Power action"
          description = "Action to run; reset applies to qemu only. startall and stopall act on guest_power_node."
          required    = true
          type        = "enum"
          enum_values = {
            start    = "start"
            stop     = "stop"
            shutdown = "shutdown"
            reboot   = "reboot"
            reset    = "reset"
            startall = "startall"
            stopall  = "stopall"
          }
        },
        {
          name        = "guest_power_node"
          title       = "Node"
          description = "Inventory host name from the proxmox group. startall and stopall only."
          required    = false
          type        = "string"
        },
        {
          name        = "guest_power_vms"
          title       = "VMIDs"
          description = "Optional comma list of VMIDs to limit startall or stopall to. Blank acts on every guest on the node."
          required    = false
          type        = "string"
        },
      ]
      description = "Power action on one guest by VMID (start, stop, shutdown, reboot, reset), or startall and stopall on one node."
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

    proxmox-benchmark-client = {
      repository       = "ansible-proxmox"
      playbook         = "playbooks/benchmark-client.yml"
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
          title       = "Client VMID"
          description = "Numeric VMID reserved for the benchmark client."
          required    = true
          type        = "string"
        },
        {
          name        = "gpu_guest_vmid"
          title       = "GPU guest VMID"
          description = "Numeric VMID used to derive the bridge, VLAN, and storage settings."
          required    = true
          type        = "string"
        },
        {
          name        = "state"
          title       = "State"
          description = "Create and configure the client, or destroy a tagged client."
          required    = true
          type        = "enum"
          enum_values = {
            present = "present"
            absent  = "absent"
          }
        },
        {
          name        = "cores"
          title       = "CPU cores"
          description = "Client CPU allocation; required when state is present."
          required    = false
          type        = "string"
        },
        {
          name        = "memory_mb"
          title       = "Memory (MB)"
          description = "Client memory allocation; required when state is present."
          required    = false
          type        = "string"
        },
        {
          name        = "disk_gb"
          title       = "Root disk (GB)"
          description = "Client root disk allocation; required when state is present."
          required    = false
          type        = "string"
        },
        {
          name        = "template"
          title       = "LXC template"
          description = "Existing Proxmox container template; required when state is present."
          required    = false
          type        = "string"
        },
        {
          name        = "images"
          title       = "Images"
          description = "Optional JSON array of digest-pinned images to pre-pull."
          required    = false
          type        = "string"
        },
        {
          name        = "tools"
          title       = "Tool versions"
          description = "Optional JSON object with pinned uv and node versions."
          required    = false
          type        = "string"
        },
        {
          name        = "engine_url"
          title       = "Engine URL"
          description = "OpenAI-compatible engine base URL ending in /v1; required when state is present."
          required    = false
          type        = "string"
        },
      ]
      description = "Create, configure, verify, or safely destroy one tagged benchmark client on a selected Proxmox node."
    }
  }
}
