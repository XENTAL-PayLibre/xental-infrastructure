variable "aws_region" {
  type        = string
  default     = "eu-west-1"
  description = "AWS region for all resources."
}

variable "github_org" {
  type        = string
  default     = "XENTAL-PayLibre"
  description = "GitHub organisation that owns the repos."
}

variable "infra_repo" {
  type        = string
  default     = "xental-infrastructure"
  description = "Infra repo name (used in the OIDC trust policy)."
}

variable "git_remote" {
  type        = string
  default     = "https://github.com/XENTAL-PayLibre/xental-infrastructure.git"
  description = "HTTPS URL the hosts clone the infra repo from."
}

variable "instance_types" {
  type = map(string)
  default = {
    staging    = "t3.small"
    production = "t3.medium"
  }
  description = "EC2 instance type per environment."
}

variable "root_volume_gb" {
  type        = number
  default     = 30
  description = "Root EBS volume size in GB."
}

variable "tags" {
  type        = map(string)
  default     = { Project = "xental", ManagedBy = "terraform" }
  description = "Tags applied to all resources."
}
