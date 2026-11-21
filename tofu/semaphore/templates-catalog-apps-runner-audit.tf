# The runner host container audit, kept in its own file because
# templates-catalog-apps.tf is at the 12 KB File Size gate. See
# templates-catalog.tf for field docs.
locals {
  ansible_templates_apps_runner_audit = {
    # Read-only: lists the runner host's containers and asserts their mounts.
    # A task's added arguments append to the template's own `--tags`, so
    # apps-github-runner cannot be narrowed to this tag; it needs its own entry.
    apps-github-runner-audit = {
      repository       = "ansible-proxmox-apps"
      playbook         = "playbooks/site.yml"
      limit            = "docker_vms"
      tags             = "runner_container_audit"
      mutating         = false
      schedule_enabled = false
      extra_args       = []
      description      = "Read-only runner host container audit, via --tags runner_container_audit."
    }
  }
}
