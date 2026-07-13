variable "organization_name" {
  description = "Terrakube organization holding every workspace (mirrors the GitHub org login)."
  type        = string
  default     = "dryvist"
}

variable "admin_group" {
  description = "OpenBao identity group granted Terrakube admin. Must match TERRAKUBE_ADMIN_GROUP in the compose env."
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
