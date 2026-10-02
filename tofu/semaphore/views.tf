# Views are the tabs across the top of the SemaphoreUI template list. They are
# the only grouping the product offers — there are no tags — so they are how a
# ref becomes visible before a run rather than after it.
#
# Per project: a deployed tab, then one per preview ref of that project's
# template repositories. The order matters: the deployed ref is position 0, so it is what
# opens by default and what someone reaching for "run the converge" gets without
# choosing anything. Preview refs sit behind it.
#
# A template's name also carries its ref, so a view is a convenience rather than
# the only signal. Neither is load-bearing on its own; together they mean a run
# from an unreleased ref cannot be started by accident.
#
# Declarative-drift audit (semaphoreui_project_view): the settable attributes
# are project_id, title and position. All three are declared. `project_id` is
# ForceNew, the same as elsewhere in this root.

locals {
  # Every distinct preview ref per project, so adding a repository on a new
  # branch produces its tab without another edit here.
  project_preview_branches = {
    for p in local.semaphore_project_names : p => sort(distinct(flatten([
      for repo in local.project_template_repos[p] : var.ansible_repositories[repo].preview_branches
    ])))
  }

  # position 0 is the deployed tab; previews follow in a stable, sorted order so
  # adding one never renumbers the others. Keyed `<project>/deployed` and
  # `<project>/<branch>`.
  project_views = merge(
    { for p in local.semaphore_project_names : "${p}/deployed" => { project = p, title = "Deployed", position = 0 } },
    merge([
      for p, branches in local.project_preview_branches : {
        for i, b in branches : "${p}/${b}" => { project = p, title = "Preview — ${b}", position = i + 1 }
      }
    ]...),
  )
}

resource "semaphoreui_project_view" "each" {
  for_each = local.project_views

  project_id = semaphoreui_project.each[each.value.project].id
  title      = each.value.title
  position   = each.value.position
}

moved {
  from = semaphoreui_project_view.deployed
  to   = semaphoreui_project_view.each["apps/deployed"]
}

moved {
  from = semaphoreui_project_view.preview["develop"]
  to   = semaphoreui_project_view.each["apps/develop"]
}
