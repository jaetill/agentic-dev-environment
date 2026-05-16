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

variable "additional_policy_arns" {
  type        = list(string)
  description = "Additional IAM policy ARNs to attach to the role (project-specific permissions)"
  default     = []
}
