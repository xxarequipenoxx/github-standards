output "repositories" {
  description = "Per repository (the six fixed modules, then the projects map keyed by repository name): enforcement of the rulesets and the required checks, for the plan review and the adoption order"
  value = {
    for name, repository in merge({
      github_standards = module.github_standards
      repo_template    = module.repo_template
      web_kit          = module.web_kit
      kubernetes_infra = module.kubernetes_infra
      onibat           = module.onibat
      ai_agentic_setup = module.ai_agentic_setup
      }, module.projects) : name => {
      full_name       = repository.full_name
      enforcement     = repository.enforcement
      required_checks = repository.required_checks
    }
  }
}
