variable "semaphore_api_base_url" {
  description = "HTTPS base URL of the Semaphore API, including the /api suffix. Supplied at apply time because the real domain is not committed."
  type        = string

  validation {
    condition     = can(regex("^https://", var.semaphore_api_base_url))
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
    condition     = can(regex("/api$", var.semaphore_api_base_url))
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
    Ansible repositories Semaphore may run, keyed by short name. `url` is the
    public clone URL and `branch` the ref templates check out. Public over
    HTTPS: nothing here needs a deploy key, which is why every repository and
    inventory references the `none`-type key.
  EOT

  type = map(object({
    url    = string
    branch = string
  }))

  default = {
    ansible-proxmox = {
      url    = "https://github.com/dryvist/ansible-proxmox.git"
      branch = "main"
    }
    ansible-proxmox-apps = {
      url    = "https://github.com/dryvist/ansible-proxmox-apps.git"
      branch = "main"
    }
    ansible-splunk = {
      url    = "https://github.com/dryvist/ansible-splunk.git"
      branch = "main"
    }
  }

  validation {
    condition     = alltrue([for r in var.ansible_repositories : can(regex("^https://", r.url))])
    error_message = "Every repository url must be an HTTPS clone URL."
  }

  validation {
    condition     = alltrue([for r in var.ansible_repositories : length(trimspace(r.branch)) > 0])
    error_message = "Every repository must name a branch; an empty branch is only valid for path-based repositories."
  }
}

variable "openbao_address" {
  description = "Internal HTTPS address of OpenBao, supplied at apply time because the real domain is not committed. Published to runs as BAO_ADDR."
  type        = string

  validation {
    condition     = can(regex("^https://", var.openbao_address))
    error_message = "openbao_address must be an HTTPS URL."
  }
}

variable "nautobot_url" {
  description = "Internal HTTPS address of Nautobot, supplied at apply time. Published to runs as NAUTOBOT_URL so the parallel Nautobot inventory and the drift report can resolve it."
  type        = string

  validation {
    condition     = can(regex("^https://", var.nautobot_url))
    error_message = "nautobot_url must be an HTTPS URL."
  }
}
