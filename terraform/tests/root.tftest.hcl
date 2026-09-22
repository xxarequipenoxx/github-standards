# The root configuration wires the five repositories; this checks the wiring, mocked.

mock_provider "github" {}

run "every_repository_starts_disabled" {
  command = plan

  assert {
    condition     = alltrue([for r in output.repositories : r.enforcement == "disabled"])
    error_message = "milestone S3 ships every ruleset disabled (README section 9); switch per repository in a later PR"
  }

  assert {
    condition     = length(output.repositories) == 5
    error_message = "five repositories are managed: github-standards, repo-template, web-kit, kubernetes-infra, Onibat"
  }

  assert {
    condition     = length(output.repositories.github_standards.required_checks) == 14 && length(output.repositories.onibat.required_checks) == 9
    error_message = "github-standards requires every self-ci check and Onibat its nine pr.yml jobs"
  }
}
