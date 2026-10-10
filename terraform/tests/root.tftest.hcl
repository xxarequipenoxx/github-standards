# The root configuration wires the six repositories; this checks the wiring, mocked.

mock_provider "github" {}

run "every_repository_starts_disabled" {
  command = plan

  assert {
    condition     = alltrue([for r in output.repositories : r.enforcement == "disabled"])
    error_message = "milestone S3 ships every ruleset disabled (README section 9); switch per repository in a later PR"
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
