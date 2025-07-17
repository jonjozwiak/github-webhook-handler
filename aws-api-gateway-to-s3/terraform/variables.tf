
variable "region" {
  description = "The AWS region to deploy the resources to"
  type        = string
  default     = "us-east-1"
}

variable "github_webhook_secret_parameter_name" {
  description = "The SSM parameter name for the GitHub webhook secret"
  type        = string
  default     = "github-webhook-secret"
}

variable "github_webhook_secret" {
  description = "The GitHub webhook secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "log_group_retention_in_days" {
  description = "The number of days to retain log events in the log group"
  type        = number
  default     = 14
}

