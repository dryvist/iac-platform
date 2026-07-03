variable "organization_name" {
  description = "Terrakube organization holding every workspace (mirrors the GitHub org login)."
  type        = string
  default     = "dryvist"
}

variable "admin_group" {
  description = "Dex group granted Terrakube admin, in the github connector's org:team-slug shape. Must match TERRAKUBE_ADMIN_GROUP in the compose env."
  type        = string
  default     = "dryvist:terrakube-admins"
}

variable "tofu_version" {
  description = "OpenTofu version every workspace runs (single fleet-wide pin; bump deliberately)."
  type        = string
  default     = "1.12.2"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.tofu_version))
    error_message = "tofu_version must be a plain semver like 1.12.2."
  }
}

variable "github_org_admin_token" {
  description = "GitHub token with admin:org for the tofu-github workspace (classic PAT for MVP; GitHub App planned). Supply via TF_VAR_github_org_admin_token at apply — no default, never committed."
  type        = string
  sensitive   = true
}

variable "ci_token_days" {
  description = "Validity window (days) for the CI team token. Rotation = re-apply after expiry."
  type        = number
  default     = 90
}
