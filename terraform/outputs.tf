output "host_public_ips" {
  description = "Elastic IP per environment — point your DNS A records here."
  value       = { for env, eip in aws_eip.host : env => eip.public_ip }
}

output "instance_ids" {
  value = { for env, i in aws_instance.host : env => i.id }
}

output "github_deploy_role_arn" {
  description = "Set this as the AWS_DEPLOY_ROLE_ARN secret in the infra repo."
  value       = aws_iam_role.deploy.arn
}
