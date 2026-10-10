# Projects created by scripts/new-repo.sh (`make new-repo`) from the latest repo-template
# release. The script applies the standard settings and active rulesets through the API
# (apply-settings.sh, same values as the module) and adds one entry to the map below in a
# pull request, with the ids of the rulesets it created; the next reviewed apply imports the
# repository and both rulesets, so the plan shows no change. Repositories with
# project-specific needs (environments) graduate to their own module call in repositories.tf.

locals {
  # Check names of the repo-template pr.yml (docs/required-checks.md, section 2). A language
  # job added to a project's pr.yml adds its own names: set required_checks on the entry.
  template_checks = [
    "commits / conventional commits",
    "security / gitleaks",
    "security / zizmor",
  ]

  # name = { description, visibility, optional enforcement, optional required_checks,
  #          optional main_ruleset_id and tags_ruleset_id (set by new-repo.sh), optional has_wiki }
  projects = {
    "lifecycle-compliance-security" = {
      description     = "Weekly compliance, obsolescence and AI security reports, AI suggestions and lifecycle tracking for all repositories"
      visibility      = "private"
      enforcement     = "active"
      main_ruleset_id = 24852328
      tags_ruleset_id = 24852331
      has_wiki        = true # weekly reports and the decisions log are published there
      required_checks = [
        "commits / conventional commits",
        "security / gitleaks",
        "security / zizmor",
        "python / lint and types",
        "python / tests (sqlite)",
        "python / dependency audit",
      ]
    }
    "ai-video-factory" = {
      description     = "Family project: automated multilingual (fr/en/es/it) video production for YouTube and TikTok, with AI agents and a human approval gate"
      visibility      = "private"
      enforcement     = "active"
      main_ruleset_id = 24856821
      tags_ruleset_id = 24856823
    }
    # new-repo.sh inserts entries above this line, keep it last
  }
}

module "projects" {
  source   = "./modules/repository"
  for_each = local.projects

  name            = each.key
  description     = each.value.description
  visibility      = each.value.visibility
  required_checks = try(each.value.required_checks, local.template_checks)
  enforcement     = try(each.value.enforcement, "disabled") # adoption order (README section 9)
  has_wiki        = try(each.value.has_wiki, false)
}

# Everything already exists when the entry lands (new-repo.sh created it): import instead
# of creating. An import of a resource already in state is a no-op. tofu test cannot import
# through a mocked provider, so the root test sets import_projects = false.
import {
  for_each = var.import_projects ? local.projects : {}
  to       = module.projects[each.key].github_repository.this
  id       = each.key
}

import {
  for_each = { for name, p in local.projects : name => p if var.import_projects && try(p.main_ruleset_id, null) != null }
  to       = module.projects[each.key].github_repository_ruleset.main
  id       = "${each.key}:${each.value.main_ruleset_id}"
}

import {
  for_each = { for name, p in local.projects : name => p if var.import_projects && try(p.tags_ruleset_id, null) != null }
  to       = module.projects[each.key].github_repository_ruleset.release_tags
  id       = "${each.key}:${each.value.tags_ruleset_id}"
}
