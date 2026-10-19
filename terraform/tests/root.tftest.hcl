# The root configuration wires the six repositories; this checks the wiring, mocked.

mock_provider "github" {}

variables {
  import_projects = false # imports are not supported by tofu test (mocked provider)
}

run "every_repository_is_active" {
  command = plan

  assert {
    condition     = alltrue([for key, repo in output.repositories : repo.enforcement == "active"])
    error_message = "every managed repository reports its required checks, so every ruleset is active (README section 9)"
  }

  assert {
    condition     = alltrue([for key, repo in output.repositories : length(repo.required_checks) > 0])
    error_message = "an active ruleset with no required check lets auto-merge merge before any check ran (auto-merge.yml)"
  }

  assert {
    condition     = alltrue([for key in ["github_standards", "repo_template", "web_kit", "kubernetes_infra", "onibat", "ai_agentic_setup"] : contains(keys(output.repositories), key)])
    error_message = "the six fixed repositories are managed: github-standards, repo-template, web-kit, kubernetes-infra, Onibat, ai-agentic-setup"
  }

  assert {
    condition     = length(output.repositories) == 6 + length(module.projects)
    error_message = "every entry of the projects map (projects.tf) is a managed repository"
  }

  assert {
    condition     = length(output.repositories.github_standards.required_checks) == 15 && length(output.repositories.onibat.required_checks) == 9 && length(output.repositories.ai_agentic_setup.required_checks) == 4
    error_message = "github-standards requires every self-ci check Onibat its nine pr.yml jobs, ai-agentic-setup its four"
  }
}
