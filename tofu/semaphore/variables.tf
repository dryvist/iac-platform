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
  description = "Name prefix of the Semaphore projects; each is \"<prefix>-<project>\" (project.tf)."
  type        = string
  default     = "homelab"
}

variable "ansible_repositories" {
  description = <<-EOT
    Ansible repositories Semaphore may run, keyed by short name.

    `url` is the public clone URL. `branch` is the DEPLOYED ref — the one the
    unsuffixed template runs and the only one anything scheduled may touch. It
    may name a branch or a release tag. Each release-tag value has a Renovate
    annotation above it that proposes the next tag.
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
      url = "https://github.com/dryvist/ansible-proxmox.git"
      # renovate: datasource=github-tags depName=dryvist/ansible-proxmox
      branch           = "v2.44.0"
      preview_branches = ["develop"]
    }
    ansible-proxmox-apps = {
      url = "https://github.com/dryvist/ansible-proxmox-apps.git"
      # renovate: datasource=github-tags depName=dryvist/ansible-proxmox-apps
      branch           = "v5.42.0"
      preview_branches = ["develop"]
    }
    ansible-secrets-management = {
      url = "https://github.com/dryvist/ansible-secrets-management.git"
      # renovate: datasource=github-tags depName=dryvist/ansible-secrets-management
      branch           = "v0.100.0"
      preview_branches = ["develop"]
    }
    ansible-proxmox-ai = {
      url = "https://github.com/dryvist/ansible-proxmox-ai.git"
      # renovate: datasource=github-tags depName=dryvist/ansible-proxmox-ai
      branch           = "v2.41.0"
      preview_branches = ["develop"]
    }
    # No develop branch upstream: this repository releases from main only, so
    # naming one here would produce a template whose every run fails to clone.
    ansible-splunk = {
      url = "https://github.com/dryvist/ansible-splunk.git"
      # renovate: datasource=github-tags depName=dryvist/ansible-splunk
      branch = "v0.118.1"
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

variable "max_parallel_tasks" {
  description = <<-EOT
    Semaphore's server-wide task concurrency ceiling. Each project's own cap
    (project.tf) is asserted to stay at or below it.

    Ansible's forks actually run in compose/docker-compose.yml's
    semaphore-runner service, sized for K=3 at mem_limit 6144m: an
    "all"-scoped template at forks=12 peaks around 250 MiB parent + 12 x 110
    MiB workers =~ 1.53 GiB, so 3 concurrent tasks fit with room to spare.
    This value and that mem_limit are one budget — raise this only in the
    same change that raises mem_limit, and by the same ratio.

    Compose and this tofu root have no common runtime source to share a
    single value from (compose reads compose/.env at deploy time; this root
    reads TF_VAR_* from the run environment), so the default below and
    compose's own &max_parallel_tasks anchor are two literals by necessity.
    tests/max_parallel_tasks_contract.tftest.hcl fails `tofu test` if they
    drift; that test is wired into this repo's own CI (.github/workflows/ci-gate.yml,
    a local job — the shared org gate deliberately never runs `tofu test`).
  EOT
  type        = number
  default     = 3

  validation {
    condition     = var.max_parallel_tasks > 0
    error_message = "max_parallel_tasks must be positive; Semaphore's own default (unset) is 9999, effectively unbounded, which is never what this project wants."
  }
}

variable "benchmark_client_node" {
  description = <<-EOT
    Published Proxmox inventory name of the node that hosts the benchmark client.

    Supplied as TF_VAR_benchmark_client_node in the run environment. Like
    openbao_address, the value is kept out of this repository.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.benchmark_client_node))
    error_message = "benchmark_client_node must be a lowercase inventory name of letters, digits and hyphens."
  }
}

variable "benchmark_client_vmid" {
  description = <<-EOT
    VMID of the running LXC tagged benchmark-client that the tau2 lanes run from.

    Supplied as TF_VAR_benchmark_client_vmid in the run environment.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9]{3,9}$", var.benchmark_client_vmid))
    error_message = "benchmark_client_vmid must be a numeric VMID of 3 to 9 digits."
  }
}

variable "benchmark_lane_guest_vmids" {
  description = <<-EOT
    VMID of the measured GPU guest for each tau2 benchmark lane, keyed by the
    guest_key that the lane names in benchmark_tau2_lanes.

    Supplied as TF_VAR_benchmark_lane_guest_vmids in the run environment, as a
    JSON object. A lane whose key is missing here fails the schedule guard.
  EOT
  type        = map(string)

  validation {
    condition     = alltrue([for v in values(var.benchmark_lane_guest_vmids) : can(regex("^[0-9]{3,9}$", v))])
    error_message = "Every benchmark_lane_guest_vmids value must be a numeric VMID of 3 to 9 digits."
  }
}

variable "benchmark_model_tokenizers" {
  description = <<-EOT
    Tokenizer identifier that interprets request lengths for each tau2
    benchmark lane, keyed by the model alias the lane sets in
    benchmark_tau2_lanes.

    The value is a model catalog fact — the hf_repo of the artifact the
    lane's model alias serves in ansible-proxmox-ai's llm-models.d — so it
    is supplied from the run environment as TF_VAR_benchmark_model_tokenizers
    and never typed as a literal here.
  EOT
  type        = map(string)

  validation {
    condition     = alltrue([for t in values(var.benchmark_model_tokenizers) : can(regex("^[A-Za-z0-9][A-Za-z0-9.-]*/[A-Za-z0-9][A-Za-z0-9._-]*$", t))])
    error_message = "Every benchmark_model_tokenizers value must be an org/name identifier from the model catalog."
  }
}

variable "benchmark_api_key_kv_path" {
  description = <<-EOT
    OpenBao KV path of the router API key that the tau2 lanes send.

    Defaults to the evals path. Override with TF_VAR_benchmark_api_key_kv_path.
  EOT
  type        = string
  default     = "apps/evals"

  validation {
    condition     = can(regex("^[A-Za-z0-9_/.-]+$", var.benchmark_api_key_kv_path))
    error_message = "benchmark_api_key_kv_path must be a KV path of letters, digits, slashes, dots, underscores and hyphens."
  }
}

variable "benchmark_api_key_kv_field" {
  description = <<-EOT
    Field name, under benchmark_api_key_kv_path, that holds the router API key.

    Defaults to the evals field. Override with TF_VAR_benchmark_api_key_kv_field.
  EOT
  type        = string
  default     = "evals_llm_router_key"

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]+$", var.benchmark_api_key_kv_field))
    error_message = "benchmark_api_key_kv_field must be a field name of letters, digits, underscores and hyphens."
  }
}

variable "benchmark_router_url" {
  description = <<-EOT
    OpenAI-compatible /v1 endpoint the tau2 lanes send their requests to.

    Supplied as TF_VAR_benchmark_router_url in the run environment.
  EOT
  type        = string

  validation {
    condition     = can(regex("^https://([a-z0-9-]+\\.)+[a-z]{2,}/v1$", var.benchmark_router_url))
    error_message = "benchmark_router_url must be https://<DNS name>/v1, with no IP address, port or extra path."
  }
}

