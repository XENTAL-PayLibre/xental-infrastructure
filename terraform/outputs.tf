output "host_public_ips" {
  description = "Elastic IP per environment. Set each as the SSH_HOST variable in the matching GitHub Environment, and point DNS A records here."
  value       = { for env, eip in aws_eip.host : env => eip.public_ip }
}

output "instance_ids" {
  value = { for env, i in aws_instance.host : env => i.id }
}

output "ssh_user" {
  description = "Login user for the hosts (set as SSH_USER in each GitHub Environment)."
  value       = "ubuntu"
}
