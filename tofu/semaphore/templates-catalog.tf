# The playbook catalog: one entry per playbook Semaphore may run.
# templates.tf turns these into resources; the header there explains the
# wrapper contract every entry rides on.
#
# Split by repository (templates-catalog-<repo>.tf) to stay under the 12 KB
# file-size gate — this file only merges the per-repository maps into the one
# `ansible_templates` map templates.tf consumes. Field documentation:
#
#   `limit` is the host pattern WITHOUT localhost; the argument list appends
#   it, so no entry here can forget it.
#
#   `mutating` drives schedules.tf. It is not a comment — a template marked
#   false is eligible to run unattended, so it is the safety property of this
#   whole file and is asserted on below.
#
#   `tags` is optional and omitted by almost every entry. Set it only when a
#   playbook must be run for some of its plays rather than in full, and only
#   after confirming each tag is carried by the play itself with a static
#   `roles:` list — `--tags` never reaches inside an untagged `include_role`,
#   and a tag that matches nothing yields a converge that runs cleanly,
#   changes nothing and reports success. A scoped entry still names the ENTRY
#   playbook (the one whose preamble loads the inventory), never an imported
#   fragment of it. A scoped entry is a second template, never an edit to the
#   full-scope one, so narrowing this file can never narrow what an existing
#   caller already gets.
#
#   `deployed_only` is currently a no-op: preview-branch (`@ <branch>`)
#   templates were dropped when the project split landed (see
#   repositories.tf) and have not been rebuilt on a per-project basis. Left
#   on the entries that had it so restoring preview-branch support later
#   does not silently un-flag them.
#
#   `project` names one of project.tf's semaphore_project_names. Required on
#   every entry — repositories.tf, inventories.tf and templates.tf all key
#   off it to resolve which project's checkout a template runs from.

locals {
  ansible_templates = merge(
    local.ansible_templates_apps,
    local.ansible_templates_proxmox,
    local.ansible_templates_splunk,
    local.ansible_templates_ai,
  )
}
