# One repository per Ansible repo Semaphore may run.
#
# Declarative-drift audit (semaphoreui_project_repository): the settable
# attributes are name, project_id, url, branch and ssh_key_id. All five are
# declared. `project_id` is ForceNew, which is harmless here — the project is
# created once and never renamed in a way that would replace it.
resource "semaphoreui_project_repository" "ansible" {
  for_each = var.ansible_repositories

  project_id = semaphoreui_project.homelab.id
  name       = each.key
  url        = each.value.url
  branch     = each.value.branch

  # Public HTTPS clone — see the None key rationale in project.tf.
  ssh_key_id = semaphoreui_project_key.none.id
}
