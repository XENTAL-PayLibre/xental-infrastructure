# Runbook: Host lifecycle

App hosts and the monitoring host are EC2 instances with Elastic IPs (stable
across stop/start). Containers auto-start on boot (restart policies).

## Stop (save cost)
```bash
aws ec2 stop-instances --region eu-west-1 --instance-ids <id...>
```
Compute billing stops. EIP + EBS still incur small charges. Same IPs on restart.

## Start (resume)
```bash
aws ec2 start-instances --region eu-west-1 --instance-ids <id...>
```
Wait ~60–90s; Docker + containers come back with the last-deployed config. No
redeploy needed. Verify per deploy.md.

## Find instance IDs
```bash
aws ec2 describe-instances --region eu-west-1 \
  --filters "Name=tag:Project,Values=xental" \
  --query "Reservations[].Instances[].[Tags[?Key=='Name']|[0].Value,InstanceId,State.Name]" \
  --output table
```

## Restart a single service (no host reboot)
```bash
cd /opt/xental-infrastructure
docker compose -f compose/docker-compose.yml -f compose/docker-compose.<env>.yml \
  --env-file env/<env>.runtime.env up -d --force-recreate <service>
```

## Resize (scale up/down)
1. Edit `instance_types` (or `monitoring_instance_type`) in `terraform/terraform.tfvars`.
2. `terraform apply` (stop/replace as prompted). Free-tier-eligible x86 types:
   `t3.small`, `m7i-flex.large`, `c7i-flex.large` (avoid `t4g.*` ARM — images are amd64).

## Replace a host (rebuild from scratch)
```bash
cd terraform
terraform taint aws_instance.host[\"staging\"]   # or [\"production\"] / aws_instance.monitoring
terraform apply
```
New instance, same EIP. Redeploy the app stack (deploy.md). DB data on the old
EBS is lost unless restored from backup (backup-restore.md).

## Full teardown (zero cost)
```bash
cd terraform && terraform destroy
```
Releases IPs + volumes. Re-`apply` later gives new IPs; the stack redeploys from
the pipeline.
