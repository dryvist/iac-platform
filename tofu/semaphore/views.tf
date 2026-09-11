# Views are the tabs across the top of the SemaphoreUI template list. They are
# the only grouping the product offers — there are no tags — so they are how a
# ref becomes visible before a run rather than after it.
#
# Two tabs, and the order matters: the deployed ref is position 0, so it is what
# opens by default and what someone reaching for "run the converge" gets without
# choosing anything. Preview refs sit behind it.
#
# A template's name also carries its ref, so a view is a convenience rather than
# the only signal. Neither is load-bearing on its own; together they mean a run
# from an unreleased ref cannot be started by accident.
#
# Declarative-drift audit (semaphoreui_project_view): the settable attributes
# are project_id, title and position. All three are declared. `project_id` is
# ForceNew, harmless for the same reason as elsewhere in this root.

locals {
  # Every distinct preview ref across all repositories, so adding a repository
  # on a new branch produces its tab without another edit here.
  preview_branches = distinct(flatten([
    for r in var.ansible_repositories : r.preview_branches
  ]))

  # position 0 is the deployed tab; previews follow in a stable, sorted order so
  # adding one never renumbers the others.
  view_positions = merge(
    { deployed = 0 },
    { for i, b in sort(local.preview_branches) : b => i + 1 },
  )
}

resource "semaphoreui_project_view" "deployed" {
  project_id = semaphoreui_project.homelab.id
  title      = "Deployed"
  position   = local.view_positions["deployed"]
}

resource "semaphoreui_project_view" "preview" {
  for_each = toset(local.preview_branches)

  project_id = semaphoreui_project.homelab.id
  title      = "Preview — ${each.value}"
  position   = local.view_positions[each.value]
}
