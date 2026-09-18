variable "semaphore_api_base_url" {
  description = <<-EOT
    HTTPS base URL of the Semaphore API, including the /api suffix.

    Optional. Left null it is derived from the base domain the store already
    holds (see locals.tf), which is what lets a remote run work without the
    real domain being committed here OR set as a workspace variable. Pass it
    explicitly only to point a run at something other than the deployed API.
  EOT
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.semaphore_api_base_url == null || can(regex("^https://", var.semaphore_api_base_url))
    error_message = "semaphore_api_base_url must be an HTTPS URL."
  }

  # The API sits behind the same Traefik forward-auth as the UI unless the
  # ingress carries a bypass for the token-authenticated paths. Semaphore's API
  # returns 401 on its own for every path except /api/ping and the /api/auth
  # browser-login surface, so the bypass is narrowed to the former and this
  # provider authenticates with its bearer token as normal. Without that bypass
  # every call here is answered by a 302 to the auth portal, which the provider
  # reports as a confusing decode error rather than as an auth failure.
  validation {
    condition     = var.semaphore_api_base_url == null || can(regex("/api$", var.semaphore_api_base_url))
    error_message = "semaphore_api_base_url must end in /api — the provider appends resource paths to it, not the /api prefix."
  }
}

variable "project_name" {
  description = "The single Semaphore project holding every Ansible repository, inventory and template."
  type        = string
  default     = "homelab"
}

variable "ansible_repositories" {
  description = <<-EOT
    Ansible repositories Semaphore may run, keyed by short name.

    `url` is the public clone URL. `branch` is the DEPLOYED ref — the one the
    unsuffixed template runs and the only one anything scheduled may touch.
    `preview_branches` names further refs the same repository may be run from
    on demand; each gets its own repository entry, its own templates and its
    own tab in the UI, so which ref a run used is never inferred.

    Public over HTTPS: nothing here needs a deploy key, which is why every
    repository and inventory references the `none`-type key.

    Only remote HTTPS origins are permitted, and the validations below enforce
    it. SemaphoreUI itself accepts `ssh`, `http`, `file` and `git` URIs and
    bare absolute paths; a path- or file-scheme repository would let a run
    execute whatever happens to be sitting on the plane's filesystem, which is
    unreviewed, unversioned and invisible to anyone reading this root. There is
    no case for it here.
  EOT

  type = map(object({
    url              = string
    branch           = string
    preview_branches = optional(list(string), [])
  }))

  default = {
    ansible-proxmox = {
      url              = "https://github.com/dryvist/ansible-proxmox.git"
      branch           = "main"
      preview_branches = ["develop"]
    }
    ansible-proxmox-apps = {
      url              = "https://github.com/dryvist/ansible-proxmox-apps.git"
      branch           = "main"
      preview_branches = ["develop"]
    }
    ansible-proxmox-ai = {
      url              = "https://github.com/dryvist/ansible-proxmox-ai.git"
      branch           = "main"
      preview_branches = ["develop"]
    }
    # No develop branch upstream: this repository releases from main only, so
    # naming one here would produce a template whose every run fails to clone.
    ansible-splunk = {
      url    = "https://github.com/dryvist/ansible-splunk.git"
      branch = "main"
    }
  }

  validation {
    condition     = alltrue([for r in var.ansible_repositories : can(regex("^https://", r.url))])
    error_message = "Every repository url must be an HTTPS clone URL. Path-based and file:// repositories are never permitted: a run must only ever execute a reviewed, pushed commit."
  }

  validation {
    condition     = alltrue([for r in var.ansible_repositories : length(trimspace(r.branch)) > 0])
    error_message = "Every repository must name a branch; an empty branch is what SemaphoreUI treats as a path-based repository."
  }

  validation {
    condition = alltrue([
      for r in var.ansible_repositories : alltrue([
        for b in r.preview_branches : length(trimspace(b)) > 0 && b != r.branch
      ])
    ])
    error_message = "Every preview branch must be non-empty and different from the deployed branch; repeating the deployed branch would create two entries racing for the same name."
  }
}

variable "openbao_address" {
  description = <<-EOT
    Internal HTTPS address of the secret store. Published to runs as BAO_ADDR,
    and the single input every other endpoint in this root is derived from.

    Supplied as TF_VAR_openbao_address in the run environment. That value is
    already present there as the store address the dynamic-credential flow
    uses, so passing it here discloses nothing new — and it keeps the real
    domain out of this repository, which is the actual requirement.
  EOT
  type        = string

  validation {
    condition     = can(regex("^https://openbao\\.[a-z0-9.-]+$", var.openbao_address))
    error_message = "openbao_address must be https://openbao.<domain> with no path or port — the Semaphore endpoint is derived from the domain inside it."
  }
}

