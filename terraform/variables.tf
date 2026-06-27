variable "aws_region" {
  type        = string
  default     = "eu-west-1"
  description = "AWS region for all resources."
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key (contents of your id_ed25519.pub) authorised on the hosts. The matching private key goes into the GitHub secret SSH_PRIVATE_KEY."
}

variable "ssh_ingress_cidr" {
  type        = string
  default     = "0.0.0.0/0"
  description = "CIDR allowed to reach port 22. GitHub-hosted runners use dynamic IPs, so this defaults to open; auth is key-only. Narrow it if you deploy from a fixed network."
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

variable "monitoring_instance_type" {
  type        = string
  default     = "t3.small"
  description = "EC2 type for the observability/monitoring host (free-tier-eligible)."
}

variable "monitoring_volume_gb" {
  type        = number
  default     = 40
  description = "Root EBS volume size (GB) for the monitoring host (metrics/logs retention)."
}

variable "tags" {
  type        = map(string)
  default     = { Project = "xental", ManagedBy = "terraform" }
  description = "Tags applied to all resources."
}
