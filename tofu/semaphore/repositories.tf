# One repository entry per (project, repo, ref) Semaphore may run.
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
# Keys: `<project>/<repo>` for the deployed ref, `<project>/<repo>@<branch>`
# for a preview ref. A project carries every ref of the repositories its
# templates run from, plus the deployed ansible-proxmox-apps ref for the shared
# inventory and both ansible-secrets-management refs in `secrets` for its
# standalone OpenBao templates. The deployed apps checkout holds
# inventory/hosts.yml, which every project's inventory points at
# (inventories.tf).
#
# Declarative-drift audit (semaphoreui_project_repository): the settable
# attributes are name, project_id, url, branch and ssh_key_id. All five are
# declared. `project_id` is ForceNew: an entry that changes project is
# recreated, and so is every template built on it (templates.tf).

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

  project_template_repos = {
    for p in local.semaphore_project_names : p => distinct([
      for t in local.ansible_templates : t.repository
      if try(t.project, local.repository_projects[t.repository]) == p
    ])
  }

  project_repository_refs = {
    for pair in flatten([
      for p in local.semaphore_project_names : [
        for rkey, r in local.repository_refs : merge(r, { key = "${p}/${rkey}", project = p })
        if contains(local.project_template_repos[p], r.repo) || rkey == "ansible-proxmox-apps" || (p == "secrets" && r.repo == "ansible-secrets-management")
      ]
    ]) : pair.key => pair
  }
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
  for_each = local.project_repository_refs

  project_id = semaphoreui_project.each[each.value.project].id

  # The ref is part of the display name, so the repository picker cannot be
  # read as ambiguous.
  name   = "${each.value.repo} (${each.value.branch})"
  url    = each.value.url
  branch = each.value.branch

  # Public HTTPS clone — see the None key rationale in project.tf.
  ssh_key_id = semaphoreui_project_key.none[each.value.project].id
}

# The single project's entries are the apps project's now (project.tf).
moved {
  from = semaphoreui_project_repository.ansible["ansible-proxmox-apps"]
  to   = semaphoreui_project_repository.ansible["apps/ansible-proxmox-apps"]
}

moved {
  from = semaphoreui_project_repository.ansible["ansible-proxmox-apps@develop"]
  to   = semaphoreui_project_repository.ansible["apps/ansible-proxmox-apps@develop"]
}
