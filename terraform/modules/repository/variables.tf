variable "name" {
  description = "Repository name as it appears on GitHub (case preserved: an existing repository such as Onibat keeps its name)"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,100}$", var.name))
    error_message = "name must use letters, digits, dots, hyphens or underscores only (1 to 100 characters)."
  }
}

variable "description" {
  description = "One-line repository description shown on GitHub"
  type        = string
  default     = null
}

variable "visibility" {
  description = "Repository visibility: private (default) or public. Rulesets on private repositories need GitHub Pro (README, section 2)"
  type        = string
  default     = "private"

  validation {
    condition     = contains(["private", "public"], var.visibility)
    error_message = "visibility must be private or public (internal needs an enterprise account)."
  }
}

variable "is_template" {
  description = "Mark the repository as a template repository (true for repo-template only)"
  type        = bool
  default     = false
}

variable "from_template" {
  description = "Create the repository from the template repository (template_owner/template_repository) at creation time only. An imported repository ignores it: the template block is excluded from drift detection and can never trigger a replacement"
  type        = bool
  default     = false
}

variable "template_owner" {
  description = "Owner of the template repository used when from_template is true (the account that owns repo-template)"
  type        = string
  default     = null
}

variable "template_repository" {
  description = "Name of the template repository used when from_template is true"
  type        = string
  default     = "repo-template"
}

variable "required_checks" {
  description = "Status check names required by the main-protection ruleset, exactly as GitHub reports them (docs/required-checks.md). Empty means no required checks yet (adoption order, README section 9)"
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.required_checks) == length(distinct(var.required_checks))
    error_message = "required_checks must not contain duplicates."
  }
}

variable "enforcement" {
  description = "Enforcement of both rulesets: disabled (default, adoption order and emergency switch) or active. evaluate is organization-only"
  type        = string
  default     = "disabled"

  validation {
    condition     = contains(["active", "disabled"], var.enforcement)
    error_message = "enforcement must be active or disabled."
  }
}

variable "environments" {
  description = "Deployment environments: name, required reviewers (numeric GitHub user and team ids, at most 6 each), and the deployment branch policy (protected branches only, or custom branch/tag patterns). No block means any branch may deploy"
  type = list(object({
    name                = string
    wait_timer          = optional(number, 0)
    prevent_self_review = optional(bool, false)
    can_admins_bypass   = optional(bool, true)
    reviewers = optional(object({
      users = optional(list(number), [])
      teams = optional(list(number), [])
    }), {})
    deployment_branch_policy = optional(object({
      protected_branches     = optional(bool, true)
      custom_branch_policies = optional(bool, false)
      branch_patterns        = optional(list(string), [])
      tag_patterns           = optional(list(string), [])
    }), null)
  }))
  default = []

  validation {
    condition     = length(var.environments) == length(distinct([for e in var.environments : e.name]))
    error_message = "environment names must be unique."
  }

  validation {
    condition = alltrue([
      for e in var.environments :
      length(e.reviewers.users) <= 6 && length(e.reviewers.teams) <= 6
    ])
    error_message = "GitHub accepts at most 6 user and 6 team reviewers per environment."
  }

  validation {
    condition = alltrue([
      for e in var.environments :
      e.deployment_branch_policy == null ? true : !(e.deployment_branch_policy.protected_branches && e.deployment_branch_policy.custom_branch_policies)
    ])
    error_message = "protected_branches and custom_branch_policies are mutually exclusive."
  }

  validation {
    condition = alltrue([
      for e in var.environments :
      e.deployment_branch_policy == null ? true : (
        e.deployment_branch_policy.custom_branch_policies ||
        (length(e.deployment_branch_policy.branch_patterns) == 0 && length(e.deployment_branch_policy.tag_patterns) == 0)
      )
    ])
    error_message = "branch_patterns and tag_patterns need custom_branch_policies = true."
  }
}

variable "actions_access_level" {
  description = "Who may call this private repository's actions and reusable workflows: none (default), user (every repository of the owner, github-standards), organization or enterprise. Ignored for public repositories, which are always callable"
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "user", "organization", "enterprise"], var.actions_access_level)
    error_message = "actions_access_level must be none, user, organization or enterprise."
  }
}

variable "has_issues" {
  description = "Enable GitHub Issues. Set explicitly: the provider treats an unset value as false and would disable the feature on the first apply"
  type        = bool
  default     = true
}

variable "has_projects" {
  description = "Enable GitHub Projects (off by default: unused, one less surface)"
  type        = bool
  default     = false
}

variable "has_wiki" {
  description = "Enable the GitHub Wiki (off by default: documentation lives in the repository)"
  type        = bool
  default     = false
}

variable "has_discussions" {
  description = "Enable GitHub Discussions (off by default)"
  type        = bool
  default     = false
}
