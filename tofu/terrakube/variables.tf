variable "organization_name" {
  description = "Terrakube organization holding every workspace (mirrors the GitHub org login)."
  type        = string
  default     = "dryvist"
}

variable "admin_group" {
  description = "Bare admin team slug. Prefixed with the org name at the resource to form the org-qualified team name (org:slug) that matches TERRAKUBE_ADMIN_GROUP in the compose env."
  type        = string
  default     = "terrakube-admins"
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

variable "terrakube_endpoint" {
  description = "HTTPS URL of the Terrakube API, supplied at apply time because the real domain is not committed."
  type        = string

  validation {
    condition     = can(regex("^https://", var.terrakube_endpoint))
    error_message = "terrakube_endpoint must be an HTTPS URL."
  }
}

variable "openbao_address" {
  description = "Internal HTTPS address of OpenBao, supplied at apply time because the real domain is not committed."
  type        = string

  validation {
    condition     = can(regex("^https://", var.openbao_address))
    error_message = "openbao_address must be an HTTPS URL."
  }
}

variable "openbao_workload_audience" {
  description = "Audience bound by every OpenBao JWT role for Terrakube job identity."
  type        = string
  default     = "openbao.workload.identity"
}

variable "openbao_workload_auth_path" {
  description = "OpenBao JWT auth mount path Terrakube logs into (auth/<path>/login). The method is mounted at 'terrakube', not the Terrakube default 'jwt'."
  type        = string
  default     = "terrakube"
}
