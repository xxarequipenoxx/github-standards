variable "github_owner" {
  description = "GitHub account that owns every managed repository (provider owner and template owner). Override with TF_VAR_github_owner for another account"
  type        = string
  default     = "xxarequipenoxx"

  validation {
    condition     = can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$", var.github_owner))
    error_message = "github_owner must be a valid GitHub login."
  }
}
