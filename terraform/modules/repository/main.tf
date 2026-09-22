# One repository: settings, the two rulesets of README section 5, Dependabot, Actions access
# and deployment environments. Everything the README calls "repository settings as code".

locals {
  # Environments keyed by name, and one entry per custom branch or tag pattern.
  environments = { for e in var.environments : e.name => e }

  deployment_policies = merge([
    for e in var.environments : merge(
      e.deployment_branch_policy == null ? {} : {
        for p in e.deployment_branch_policy.branch_patterns :
        "${e.name}:branch:${p}" => { environment = e.name, branch_pattern = p, tag_pattern = null }
      },
      e.deployment_branch_policy == null ? {} : {
        for p in e.deployment_branch_policy.tag_patterns :
        "${e.name}:tag:${p}" => { environment = e.name, branch_pattern = null, tag_pattern = p }
      },
    )
  ]...)
}

resource "github_repository" "this" {
  name        = var.name
  description = var.description
  visibility  = var.visibility
  is_template = var.is_template

  has_issues      = var.has_issues
  has_projects    = var.has_projects
  has_wiki        = var.has_wiki
  has_discussions = var.has_discussions

  # Squash only: the PR title becomes the commit on main and drives the version bump.
  allow_merge_commit          = false
  allow_rebase_merge          = false
  allow_squash_merge          = true
  squash_merge_commit_title   = "PR_TITLE"
  squash_merge_commit_message = "PR_BODY"
  delete_branch_on_merge      = true
  allow_auto_merge            = true
  allow_update_branch         = true

  # Destroying the resource archives the repository instead of deleting it, and
  # prevent_destroy below refuses the destroy in the first place.
  archive_on_destroy = true

  # Only at creation: the template block is ForceNew, so it must never enter drift detection
  # on an imported repository (lifecycle.ignore_changes below).
  dynamic "template" {
    for_each = var.from_template ? [1] : []
    content {
      owner                = var.template_owner
      repository           = var.template_repository
      include_all_branches = false
    }
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [template]

    precondition {
      condition     = !var.from_template || var.template_owner != null
      error_message = "from_template needs template_owner."
    }
  }
}

# Ruleset main-protection (README section 5): the default branch only changes through a
# squash-merged pull request whose required checks are green; no bypass actor.
resource "github_repository_ruleset" "main" {
  name        = "main-protection"
  repository  = github_repository.this.name
  target      = "branch"
  enforcement = var.enforcement

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    deletion                = true
    non_fast_forward        = true
    required_linear_history = true
    required_signatures     = true

    pull_request {
      required_approving_review_count   = 0
      dismiss_stale_reviews_on_push     = true
      required_review_thread_resolution = true
      allowed_merge_methods             = ["squash"]
    }

    # GitHub requires at least one check inside the block, so the block itself is absent
    # while the list is empty (adoption order, README section 9).
    dynamic "required_status_checks" {
      for_each = length(var.required_checks) > 0 ? [1] : []
      content {
        strict_required_status_checks_policy = true

        dynamic "required_check" {
          for_each = toset(var.required_checks)
          content {
            context = required_check.value
          }
        }
      }
    }
  }
}

# Ruleset release-tags (README section 5): a published version never disappears or moves.
# Creation is deliberately not restricted: the release workflow creates the tags with the
# GITHUB_TOKEN and restricting creation would need a bypass actor.
resource "github_repository_ruleset" "release_tags" {
  name        = "release-tags"
  repository  = github_repository.this.name
  target      = "tag"
  enforcement = var.enforcement

  conditions {
    ref_name {
      include = ["refs/tags/v*"]
      exclude = []
    }
  }

  rules {
    deletion         = true
    update           = true
    non_fast_forward = true
  }
}

resource "github_repository_vulnerability_alerts" "this" {
  repository = github_repository.this.name
  enabled    = true
}

# Security updates need the alerts first.
resource "github_repository_dependabot_security_updates" "this" {
  repository = github_repository.this.name
  enabled    = true

  depends_on = [github_repository_vulnerability_alerts.this]
}

# The access level only exists on non-public repositories (public ones are always callable).
resource "github_actions_repository_access_level" "this" {
  count = var.visibility == "public" ? 0 : 1

  repository   = github_repository.this.name
  access_level = var.actions_access_level
}

resource "github_repository_environment" "this" {
  for_each = local.environments

  repository          = github_repository.this.name
  environment         = each.value.name
  wait_timer          = each.value.wait_timer
  prevent_self_review = each.value.prevent_self_review
  can_admins_bypass   = each.value.can_admins_bypass

  dynamic "reviewers" {
    for_each = length(each.value.reviewers.users) + length(each.value.reviewers.teams) > 0 ? [each.value.reviewers] : []
    content {
      users = reviewers.value.users
      teams = reviewers.value.teams
    }
  }

  dynamic "deployment_branch_policy" {
    for_each = each.value.deployment_branch_policy == null ? [] : [each.value.deployment_branch_policy]
    content {
      protected_branches     = deployment_branch_policy.value.protected_branches
      custom_branch_policies = deployment_branch_policy.value.custom_branch_policies
    }
  }
}

resource "github_repository_environment_deployment_policy" "this" {
  for_each = local.deployment_policies

  repository     = github_repository.this.name
  environment    = github_repository_environment.this[each.value.environment].environment
  branch_pattern = each.value.branch_pattern
  tag_pattern    = each.value.tag_pattern
}
