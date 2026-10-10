# Projects created from repo-template by scripts/new-repo.sh (`make new-repo`). The script
# creates the repository with `gh repo create --template` and adds one entry to the map
# below in a pull request; the next reviewed apply imports the repository and applies the
# standard settings and rulesets. Repositories with project-specific needs (required checks
# beyond the template's, environments) graduate to their own module call in repositories.tf.

locals {
  # Check names of the repo-template pr.yml (docs/required-checks.md, section 2). A language
  # job added to a project's pr.yml adds its own names: set required_checks on the entry.
  template_checks = [
    "commits / conventional commits",
    "security / gitleaks",
    "security / zizmor",
  ]

  # name = { description, visibility, optional enforcement, optional required_checks }
  projects = {
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
}

# The repository already exists when its entry lands (new-repo.sh created it): import it
# instead of creating it. An import of a resource already in state is a no-op.
import {
  for_each = local.projects
  to       = module.projects[each.key].github_repository.this
  id       = each.key
}
