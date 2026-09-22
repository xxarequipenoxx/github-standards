# Root of "repositories as code" (README section 6). Authentication is the GITHUB_TOKEN
# environment variable (fine-grained token, see terraform/README.md): no token argument,
# nothing in variables files, nothing in state beyond what the API returns.
#
# Trap: with no GITHUB_TOKEN set, provider 6.x silently falls back to `gh auth token`, which
# is the broad OAuth token of the GitHub CLI. Export GITHUB_TOKEN before every command.

terraform {
  required_version = "~> 1.12"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.13.0" # verified 2026-09-22 on the registry; .terraform.lock.hcl pins 6.13.0
    }
  }
}

provider "github" {
  owner = var.github_owner
}
