variable "project_name" {
  type        = string
  description = "Project name (used in role name and resource ARN scoping)"
}

variable "env" {
  type        = string
  description = "Environment: dev, staging, or prod"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.env)
    error_message = "env must be one of: dev, staging, prod"
  }
}

variable "github_repo" {
  type        = string
  description = "GitHub repo in the form 'org/repo' (used to scope the trust policy)"
}

variable "github_branch" {
  type        = string
  description = "Branch that may assume this role (typically 'main')"
  default     = "main"
}

variable "github_environments" {
  type        = list(string)
  description = "GitHub Environments whose deploy jobs may assume this role. Jobs running in an environment present an environment-form OIDC sub (repo:<org/repo>:environment:<name>) instead of the ref form, so gated prod deploys (ADR-0043) need this. Defaults to [] — fail closed (#214/#215): a role trusts environment-form subs only when a consumer sets this explicitly, so a non-prod role never silently inherits production trust. Set [\"production\"] (or the relevant environment) on prod roles that deploy through a protected GitHub Environment."
  default     = []
}

variable "additional_policy_arns" {
  type        = list(string)
  description = "Additional IAM policy ARNs to attach to the role (project-specific permissions)"
  default     = []
}

variable "deny_data_plane_reads" {
  type        = bool
  description = "When true, attaches an inline policy that explicitly Denies data-plane content-read actions that ReadOnlyAccess grants but `tofu plan -refresh-only` does not need — least-privilege hardening for drift-detection roles per #297. Default false means existing consumers are UNCHANGED until they opt in."
  default     = false
}
