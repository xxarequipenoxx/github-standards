# One module call per repository. All six repositories already exist on GitHub: import them
# before the first apply (terraform/README.md, step 4), never let a plan create them.
#
# Adoption order (README section 9): every ruleset starts with enforcement = "disabled";
# required_checks are the names GitHub reports on a real pull request; switch to "active"
# per repository once the checks are known to report. All six report them now: active.

locals {
  # Names produced by self-ci.yml, one per row of docs/required-checks.md section 3.
  github_standards_checks = [
    "actionlint and zizmor",
    "commits / conventional commits",
    "security / gitleaks",
    "security / zizmor",
    "python / lint and types",
    "python / tests (sqlite)",
    "python / tests (postgresql 17)",
    "python / dependency audit",
    "container / container build",
    "manifests / oci manifests",
    "opentofu / opentofu",
    "kubernetes / kustomize and kubeconform",
    "kubernetes / sops encrypted",
    "terraform / opentofu",
    "hook tests",
  ]

  # The nine jobs of the current Onibat pr.yml (local jobs, so the check name is the job
  # name). claude-review and the mobile workflow are deliberately not required.
  onibat_checks = [
    "conventional commits",
    "syntax and static analysis",
    "tests (sqlite)",
    "tests (postgres)",
    "browsers (chromium)",
    "browsers (firefox)",
    "browsers (webkit)",
    "dependency audit",
    "container build",
  ]

  # The four jobs of ai-agentic-setup pr.yml (local jobs, inlined until it calls the
  # reusable workflows of this repository). Names read from its first pull request.
  ai_agentic_setup_checks = [
    "conventional commits",
    "governance self-check",
    "actionlint and zizmor",
    "gitleaks",
  ]
}

module "github_standards" {
  source = "./modules/repository"

  name                 = "github-standards"
  description          = "Shared engineering standards: reusable GitHub Actions workflows, repository rulesets as code, Renovate preset, pre-commit hooks"
  visibility           = "public" # public projects call its workflows (docs/adopting.md, section 1)
  actions_access_level = "user"   # ignored while public; applies again if it ever turns private
  required_checks      = local.github_standards_checks
  enforcement          = "active"
}

module "repo_template" {
  source = "./modules/repository"

  name            = "repo-template"
  description     = "Template repository for new projects: thin caller workflows, commitizen, pre-commit, agent conventions"
  visibility      = "private"
  is_template     = true
  required_checks = local.template_checks
  enforcement     = "active"
}

module "web_kit" {
  source = "./modules/repository"

  name            = "web-kit"
  description     = "Web template kit: HTML5 design system, Jinja2 layouts, FR/EN i18n, PWA, visual and accessibility tests"
  visibility      = "private"
  required_checks = local.template_checks # pr.yml: the template callers
  enforcement     = "active"
}

module "kubernetes_infra" {
  source = "./modules/repository"

  name            = "kubernetes-infra"
  description     = "GitOps platform on managed Kubernetes: OpenTofu for the cloud resources, Flux for everything in the cluster"
  visibility      = "private"
  required_checks = local.template_checks # pr.yml: the template callers
  enforcement     = "active"
}

# Existing repository, imported (README section 6): the name keeps its capital letter.
module "onibat" {
  source = "./modules/repository"

  name            = "Onibat"
  description     = "Website, back-office, CRM, quoting and automation platform for Onibat"
  visibility      = "private"
  required_checks = local.onibat_checks
  enforcement     = "active"
}

module "ai_agentic_setup" {
  source = "./modules/repository"

  name            = "ai-agentic-setup"
  description     = "AI governance: vendor-neutral standards, agents and skills for Claude Code, Codex CLI and Gemini CLI"
  visibility      = "private"
  required_checks = local.ai_agentic_setup_checks
  enforcement     = "active"
}
