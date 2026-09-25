# One repository checkout per (project, repo) pair.
#
# Scope cut, stated plainly: this pass covers the DEPLOYED branch only. The
# previous single-project root also declared a second repository entry per
# preview branch (ansible_repositories[*].preview_branches, e.g.
# "ansible-proxmox-apps@develop") so an unreleased ref could be run on
# demand, with its own template set and its own UI tab (views.tf). That
# preview-branch machinery is DROPPED here, not carried into the per-project
# cross product — doing so would multiply project x repo x branch, on top of
# the "every project also needs ansible-proxmox-apps for its inventory
# loader" duplication below. If on-demand preview-branch runs are still
# wanted after the split, that is a follow-up, scoped and reviewed on its
# own, not a silent casualty of this one.
#
# Declarative-drift audit (semaphoreui_project_repository): the settable
# attributes are name, project_id, url, branch and ssh_key_id. All five are
# declared. `project_id` is ForceNew — harmless when a project is created
# once, but here it also means this resource cannot be given a new project_id
# in place: moving a repository (or anything keyed off it) from one project
# to another is a destroy-and-recreate, not an in-place move. See templates.tf
# for what that means for template IDs.
locals {
  # Every project needs ansible-proxmox-apps checked out, whether or not any
  # of its own templates run from that repo: inventory/hosts.yml lives there,
  # and every playbook (regardless of which repository it ships from) imports
  # load_tofu.yml as its first play to populate the inventory from it — see
  # inventories.tf. "apps" and "secrets" use that same checkout as their
  # template repository too; "pve", "observability" and "ai" check it out a
  # second time solely for the loader.
  project_repo_names = {
    for p in local.semaphore_project_names : p => distinct(concat(
      [for k, t in local.ansible_templates : t.repository if t.project == p],
      ["ansible-proxmox-apps"],
    ))
  }

  project_repos = {
    for pair in flatten([
      for p, repos in local.project_repo_names : [
        for r in repos : { key = "${p}/${r}", project = p, repo = r }
      ]
    ]) : pair.key => pair
  }
}

resource "terraform_data" "repository_origin_guard" {
  lifecycle {
    precondition {
      condition = alltrue([
        for pair in local.project_repos :
        startswith(var.ansible_repositories[pair.repo].url, "https://") &&
        length(trimspace(var.ansible_repositories[pair.repo].branch)) > 0
      ])
      error_message = "Every Semaphore repository must be a remote HTTPS origin with a named branch. A path-based or file:// repository would run whatever is on the plane's filesystem, which nothing reviews and nothing versions."
    }
  }
}

resource "semaphoreui_project_repository" "each" {
  for_each = local.project_repos

  project_id = semaphoreui_project.each[each.value.project].id
  name       = each.value.repo
  url        = var.ansible_repositories[each.value.repo].url
  branch     = var.ansible_repositories[each.value.repo].branch

  # Public HTTPS clone — see the None key rationale in project.tf.
  ssh_key_id = semaphoreui_project_key.each[each.value.project].id
}
