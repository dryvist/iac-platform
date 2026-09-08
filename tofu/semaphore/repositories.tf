# One repository entry per (repo, ref) Semaphore may run.
#
# Semaphore binds a ref to the REPOSITORY, not to the run: a template inherits
# whichever branch its repository names, and the task list shows the commit it
# landed on but not the branch it came from. So the only way to make "which ref
# did this run use" legible is to give each ref its own entry and put the ref in
# the name. `templates.tf` then names the ref in the template too, and
# `views.tf` puts it in a tab.
#
# The alternative the provider offers is `git_branch` on the template, which
# overrides the repository's branch invisibly. It is deliberately unused — see
# the drift audit at the top of templates.tf.
#
# Keys: the deployed ref keeps the bare repository name, so every existing
# reference (inventories.tf, the Nautobot template) resolves unchanged and no
# entry is replaced. Preview refs are keyed `<repo>@<branch>`.
#
# Declarative-drift audit (semaphoreui_project_repository): the settable
# attributes are name, project_id, url, branch and ssh_key_id. All five are
# declared. `project_id` is ForceNew, which is harmless here — the project is
# created once and never renamed in a way that would replace it.

locals {
  # Flattened (repo, ref) pairs. `deployed` is the safety property this file
  # exports: schedules.tf may only ever reach a template built from one.
  repository_refs = merge(
    {
      for name, r in var.ansible_repositories : name => {
        repo     = name
        url      = r.url
        branch   = r.branch
        deployed = true
      }
    },
    {
      for pair in flatten([
        for name, r in var.ansible_repositories : [
          for b in r.preview_branches : {
            key    = "${name}@${b}"
            repo   = name
            url    = r.url
            branch = b
          }
        ]
        ]) : pair.key => {
        repo     = pair.repo
        url      = pair.url
        branch   = pair.branch
        deployed = false
      }
    },
  )
}

# The url validation on the variable covers what is declared here. It cannot
# see a repository somebody adds in the UI, so assert the invariant against the
# resolved set as well: a future edit that builds a url rather than copying one
# still fails at plan time rather than at clone time.
resource "terraform_data" "repository_origin_guard" {
  lifecycle {
    precondition {
      condition = alltrue([
        for r in local.repository_refs :
        startswith(r.url, "https://") && length(trimspace(r.branch)) > 0
      ])
      error_message = "Every Semaphore repository must be a remote HTTPS origin with a named branch. A path-based or file:// repository would run whatever is on the plane's filesystem, which nothing reviews and nothing versions."
    }
  }
}

resource "semaphoreui_project_repository" "ansible" {
  for_each = local.repository_refs

  project_id = semaphoreui_project.homelab.id

  # The ref is part of the display name, so the repository picker cannot be
  # read as ambiguous.
  name   = "${each.value.repo} (${each.value.branch})"
  url    = each.value.url
  branch = each.value.branch

  # Public HTTPS clone — see the None key rationale in project.tf.
  ssh_key_id = semaphoreui_project_key.none.id
}
