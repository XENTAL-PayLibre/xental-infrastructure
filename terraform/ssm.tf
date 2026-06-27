# Secret parameters consumed at deploy time by render-env.sh / deploy.sh.
#
# Terraform creates them with a placeholder so the hierarchy exists and is
# IAM-scoped; the REAL values are set out-of-band (CLI/console) and Terraform
# deliberately ignores value drift so secrets never live in state/VCS:
#
#   aws ssm put-parameter --overwrite --type SecureString \
#     --name /xental/staging/POSTGRES_PASSWORD --value '...'
#
locals {
  # name => applies-to-environments
  secret_names = {
    POSTGRES_PASSWORD       = ["staging", "production"]
    XENTAL_DB_PASSWORD      = ["staging", "production"]
    PAYLIBRE_DB_PASSWORD    = ["staging", "production"]
    REDIS_PASSWORD          = ["staging", "production"]
    GITHUB_TOKEN            = ["staging", "production"]
    GHCR_TOKEN              = ["staging", "production"]
    GHCR_USER               = ["staging", "production"]
    TRAEFIK_DASHBOARD_AUTH  = ["staging"]
  }

  # Flatten to { "<env>/<name>" => {env, name} }.
  secret_params = merge([
    for name, envs in local.secret_names : {
      for env in envs : "${env}/${name}" => { env = env, name = name }
    }
  ]...)
}

resource "aws_ssm_parameter" "secret" {
  for_each = local.secret_params

  name  = "/xental/${each.value.env}/${each.value.name}"
  type  = "SecureString"
  value = "CHANGEME" # placeholder; set the real value out-of-band
  tags  = merge(var.tags, { Environment = each.value.env })

  lifecycle {
    ignore_changes = [value] # real secret managed outside Terraform
  }
}
