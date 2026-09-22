# Fixture for opentofu.yml: a module with one variable, one null resource and one output,
# tested with `tofu test` against a mocked provider (no real resource is ever created).

terraform {
  required_version = ">= 1.12.0"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "3.2.4"
    }
  }
}

variable "name" {
  description = "Name recorded in the fixture resource"
  type        = string
  default     = "fixture"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.name))
    error_message = "name must be lowercase kebab-case."
  }
}

resource "null_resource" "fixture" {
  triggers = {
    name = var.name
  }
}

output "name" {
  description = "The recorded name"
  value       = null_resource.fixture.triggers["name"]
}
