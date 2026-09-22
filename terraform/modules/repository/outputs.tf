output "name" {
  description = "Repository name"
  value       = github_repository.this.name
}

output "full_name" {
  description = "owner/name of the repository"
  value       = github_repository.this.full_name
}

output "html_url" {
  description = "Web URL of the repository"
  value       = github_repository.this.html_url
}

output "repo_id" {
  description = "Numeric GitHub id of the repository"
  value       = github_repository.this.repo_id
}

output "node_id" {
  description = "GraphQL node id of the repository"
  value       = github_repository.this.node_id
}

output "enforcement" {
  description = "Enforcement applied to both rulesets (active or disabled)"
  value       = var.enforcement
}

output "required_checks" {
  description = "Status checks required by the main-protection ruleset"
  value       = var.required_checks
}

output "main_ruleset_id" {
  description = "Id of the main-protection ruleset (import address: <repository>:<id>)"
  value       = github_repository_ruleset.main.ruleset_id
}

output "release_tags_ruleset_id" {
  description = "Id of the release-tags ruleset (import address: <repository>:<id>)"
  value       = github_repository_ruleset.release_tags.ruleset_id
}

output "environments" {
  description = "Names of the deployment environments managed for the repository"
  value       = keys(github_repository_environment.this)
}
