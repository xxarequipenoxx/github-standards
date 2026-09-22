# Provider contract of the module. The root configures the provider (owner, token from the
# GITHUB_TOKEN environment variable); the module only declares what it needs.

terraform {
  required_version = "~> 1.12"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 6.13" # verified 2026-09-22: 6.13.0 is the current 6.x release
    }
  }
}
