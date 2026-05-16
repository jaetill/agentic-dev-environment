variable "function_name" {
  type        = string
  description = "Lambda function name (e.g., '<project>-<env>')"
}

variable "env" {
  type        = string
  description = "Environment: dev, staging, or prod"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.env)
    error_message = "env must be one of: dev, staging, prod"
  }
}

variable "handler" {
  type        = string
  description = "Lambda handler module path (e.g., 'myproject.main.app')"
}

variable "runtime" {
  type        = string
  description = "Lambda runtime"
  default     = "python3.12"
}

variable "memory_size" {
  type        = number
  description = "Lambda memory size in MB"
  default     = 512
}

variable "timeout" {
  type        = number
  description = "Lambda timeout in seconds"
  default     = 30
}

variable "deployment_package_path" {
  type        = string
  description = "Path to the Lambda deployment .zip"
}

variable "release_version" {
  type        = string
  description = "Application release version (passed via env var; usually a Git tag)"
  default     = "unknown"
}

variable "environment_variables" {
  type        = map(string)
  description = "Lambda function env vars. Don't put secrets here — use secret_arns + AWS Secrets Manager."
  default     = {}
}

variable "secret_arns" {
  type        = list(string)
  description = "List of Secrets Manager secret ARNs the function needs read access to"
  default     = []
}

variable "additional_policy_arns" {
  type        = list(string)
  description = "Additional managed-policy ARNs for the execution role"
  default     = []
}

variable "additional_layers" {
  type        = list(string)
  description = "Additional Lambda layer ARNs (Insights layer is added automatically)"
  default     = []
}

variable "insights_layer_version" {
  type        = number
  description = "Lambda Insights extension layer version. Check current at https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Lambda-Insights-extension-versions.html — bumped via dep-watcher."
  default     = 53
}

variable "insights_layer_arch" {
  type        = string
  description = "Lambda Insights layer architecture: 'x86_64' or 'arm64'. Must match the Lambda function architecture."
  default     = "x86_64"
  validation {
    condition     = contains(["x86_64", "arm64"], var.insights_layer_arch)
    error_message = "insights_layer_arch must be 'x86_64' or 'arm64'"
  }
}

variable "vpc_config" {
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  description = "VPC config for the Lambda (optional)"
  default     = null
}

variable "create_api_gateway" {
  type        = bool
  description = "Whether to create an API Gateway HTTP API in front of the Lambda. Set false for event-driven Lambdas (S3, EventBridge, etc.)"
  default     = true
}

variable "cors_allow_origins" {
  type        = list(string)
  description = "CORS allowed origins for the API Gateway"
  default     = ["*"] # Project should narrow this for production
}

variable "throttle_rate_limit" {
  type        = number
  description = "API Gateway sustained rate limit (requests/second)"
  default     = 1000
}

variable "throttle_burst_limit" {
  type        = number
  description = "API Gateway burst capacity"
  default     = 2000
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all created resources"
  default     = {}
}
