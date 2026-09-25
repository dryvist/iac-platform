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
  }
}
