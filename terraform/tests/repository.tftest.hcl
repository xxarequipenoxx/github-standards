# Unit tests of modules/repository against a mocked provider: no GitHub call, no token.
# Every run plans the module directly with the defaults unless stated otherwise.

mock_provider "github" {}

variables {
  name        = "fixture"
  description = "fixture repository"
}

run "squash_only_settings" {
  command = plan

  module {
    source = "./modules/repository"
  }

  assert {
    condition     = github_repository.this.allow_squash_merge && !github_repository.this.allow_merge_commit && !github_repository.this.allow_rebase_merge
    error_message = "squash must be the only merge method on the repository"
  }

  assert {
    condition     = github_repository.this.squash_merge_commit_title == "PR_TITLE" && github_repository.this.squash_merge_commit_message == "PR_BODY"
    error_message = "the squash commit must be built from the PR title and body"
  }

  assert {
    condition     = github_repository.this.delete_branch_on_merge && github_repository.this.allow_auto_merge && github_repository.this.allow_update_branch
    error_message = "delete branch on merge, auto-merge and update branch must be on"
  }

  assert {
    condition     = github_repository.this.archive_on_destroy
    error_message = "destroy must archive, never delete"
  }

  assert {
    condition     = github_repository_ruleset.main.rules[0].pull_request[0].allowed_merge_methods == tolist(["squash"])
    error_message = "the main-protection ruleset must allow squash merges only"
  }
}

run "zero_required_approvals" {
  command = plan

  module {
    source = "./modules/repository"
  }

  assert {
    condition     = github_repository_ruleset.main.rules[0].pull_request[0].required_approving_review_count == 0
    error_message = "a single maintainer cannot approve their own PR: required approvals must be 0"
  }

  assert {
    condition     = github_repository_ruleset.main.rules[0].pull_request[0].dismiss_stale_reviews_on_push && github_repository_ruleset.main.rules[0].pull_request[0].required_review_thread_resolution
    error_message = "stale reviews must be dismissed and conversations resolved"
  }

  assert {
    condition     = github_repository_ruleset.main.rules[0].deletion && github_repository_ruleset.main.rules[0].non_fast_forward && github_repository_ruleset.main.rules[0].required_linear_history && github_repository_ruleset.main.rules[0].required_signatures
    error_message = "main-protection must block deletions and force pushes and require linear history and signatures"
  }

  assert {
    condition     = length(github_repository_ruleset.main.bypass_actors) == 0
    error_message = "the bypass list must stay empty"
  }
}

run "tag_ruleset_does_not_restrict_creation" {
  command = plan

  module {
    source = "./modules/repository"
  }

  assert {
    condition     = github_repository_ruleset.release_tags.target == "tag" && github_repository_ruleset.release_tags.conditions[0].ref_name[0].include == tolist(["refs/tags/v*"])
    error_message = "release-tags must target refs/tags/v*"
  }

  assert {
    condition     = github_repository_ruleset.release_tags.rules[0].deletion && github_repository_ruleset.release_tags.rules[0].update && github_repository_ruleset.release_tags.rules[0].non_fast_forward
    error_message = "a published tag must never be deleted or moved"
  }

  assert {
    condition     = github_repository_ruleset.release_tags.rules[0].creation == null || github_repository_ruleset.release_tags.rules[0].creation == false
    error_message = "the release workflow creates tags with the GITHUB_TOKEN: creation must not be restricted"
  }
}

run "prevent_destroy_present" {
  command = plan

  module {
    source = "./modules/repository"
  }

  # lifecycle is not a plannable attribute, so the guard is checked in the source itself.
  assert {
    condition     = can(regex("(?s)resource \"github_repository\" \"this\".*lifecycle\\s*\\{\\s*prevent_destroy\\s*=\\s*true", file("${path.module}/main.tf")))
    error_message = "github_repository.this must carry lifecycle { prevent_destroy = true }"
  }
}

run "enforcement_disabled_by_default" {
  command = plan

  module {
    source = "./modules/repository"
  }

  assert {
    condition     = github_repository_ruleset.main.enforcement == "disabled" && github_repository_ruleset.release_tags.enforcement == "disabled"
    error_message = "both rulesets must start disabled (adoption order, README section 9)"
  }

  assert {
    condition     = length(github_repository_ruleset.main.rules[0].required_status_checks) == 0
    error_message = "with no required_checks the required_status_checks block must be absent"
  }
}

run "required_checks_rendered_into_the_ruleset" {
  command = plan

  module {
    source = "./modules/repository"
  }

  variables {
    enforcement     = "active"
    required_checks = ["commits / conventional commits", "security / gitleaks"]
  }

  assert {
    condition     = github_repository_ruleset.main.enforcement == "active"
    error_message = "enforcement must follow the variable"
  }

  assert {
    condition     = github_repository_ruleset.main.rules[0].required_status_checks[0].strict_required_status_checks_policy
    error_message = "required checks must be strict (branch up to date)"
  }

  assert {
    condition     = toset([for c in github_repository_ruleset.main.rules[0].required_status_checks[0].required_check : c.context]) == toset(["commits / conventional commits", "security / gitleaks"])
    error_message = "every required check must be rendered as a required_check context"
  }
}

run "actions_access_and_dependabot" {
  command = plan

  module {
    source = "./modules/repository"
  }

  variables {
    actions_access_level = "user"
  }

  assert {
    condition     = github_actions_repository_access_level.this[0].access_level == "user"
    error_message = "actions_access_level must reach the access level resource"
  }

  assert {
    condition     = github_repository_vulnerability_alerts.this.enabled && github_repository_dependabot_security_updates.this.enabled
    error_message = "vulnerability alerts and Dependabot security updates must be enabled"
  }
}

run "template_only_when_requested" {
  command = plan

  module {
    source = "./modules/repository"
  }

  variables {
    from_template  = true
    template_owner = "fixture-owner"
  }

  assert {
    condition     = github_repository.this.template[0].owner == "fixture-owner" && github_repository.this.template[0].repository == "repo-template"
    error_message = "from_template must render the template block from template_owner and template_repository"
  }
}

run "environments_with_reviewers_and_patterns" {
  command = plan

  module {
    source = "./modules/repository"
  }

  variables {
    environments = [
      {
        name      = "production"
        reviewers = { users = [1] }
        deployment_branch_policy = {
          protected_branches     = false
          custom_branch_policies = true
          branch_patterns        = ["main"]
          tag_patterns           = ["v*"]
        }
      },
      { name = "preview" },
    ]
  }

  assert {
    condition     = github_repository_environment.this["production"].reviewers[0].users == toset([1])
    error_message = "reviewers must be rendered for the production environment"
  }

  assert {
    condition     = length(github_repository_environment.this["preview"].reviewers) == 0 && length(github_repository_environment.this["preview"].deployment_branch_policy) == 0
    error_message = "an environment without reviewers or policy must render neither block"
  }

  assert {
    condition     = github_repository_environment_deployment_policy.this["production:branch:main"].branch_pattern == "main" && github_repository_environment_deployment_policy.this["production:tag:v*"].tag_pattern == "v*"
    error_message = "custom branch and tag patterns must become deployment policies"
  }
}

run "rejects_unknown_enforcement" {
  command = plan

  module {
    source = "./modules/repository"
  }

  variables {
    enforcement = "evaluate"
  }

  expect_failures = [var.enforcement]
}

run "rejects_from_template_without_owner" {
  command = plan

  module {
    source = "./modules/repository"
  }

  variables {
    from_template = true
  }

  expect_failures = [github_repository.this]
}
