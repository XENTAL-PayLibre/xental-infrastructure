# Runbook: Incident response

Triggered by a Slack alert in `#alerts` or a user report.

## 1. Triage (what & where)
- Read the Slack alert: `alertname`, `env`, `instance`, `summary`.
- Open Grafana → **Xental Platform Overview** (SSH-tunnel to the monitoring host).
- Classify: which env (staging/production), which service, severity.

## 2. Confirm scope
```bash
ssh -i ~/.ssh/xental_deploy ubuntu@<host-ip>
cd /opt/xental-infrastructure
docker compose -f compose/docker-compose.yml -f compose/docker-compose.<env>.yml \
  --env-file env/<env>.runtime.env ps
docker run --rm --network xental-internal curlimages/curl -fsS http://xental-api:8080/health
```
Logs: Grafana → Explore → Loki → `{env="<env>", job="<service>"} |= "ERROR"`.

## 3. Common incidents
| Alert | First checks | Likely fix |
|---|---|---|
| `ServiceDown` / `EndpointDown` | `docker ps`, container logs | restart service; if a bad release → rollback.md |
| `HostHighMemory` / `HostHighCpu` | `docker stats`, top containers | restart offender; resize host (host-lifecycle.md) |
| `HostDiskFull` | `df -h`, `docker system df` | `docker system prune -f`; rotate logs; grow EBS |
| `ContainerRestartLooping` | `docker logs <name> --tail 100` | fix config/secret; rollback |
| `TlsCertExpiringSoon` | Traefik logs; DNS | redeploy so Traefik renews; check ACME |
| DB connection errors | postgres health; secret correctness | verify DB up; rotate/repair secret (secret-rotation.md) |

## 4. Mitigate
- Bad release → **rollback** (rollback.md).
- Resource exhaustion → restart container / prune / resize.
- Restart one service:
  `docker compose ... up -d --force-recreate <service>`

## 5. Resolve & verify
- Confirm health 200 and the Slack alert resolves (green).
- Confirm in Grafana the metric/log returns to normal.

## 6. After action
- Note timeline, root cause, fix.
- File a follow-up (alert tuning, capacity, migration safety).
- If a new failure mode: add/adjust an alert in
  `xental-observability/prometheus/alerts.yml`.

## Escalation / access
- App hosts: SSH key `~/.ssh/xental_deploy`, or AWS SSM Session Manager (break-glass).
- Monitoring: `ssh -L 3000:localhost:3000 ubuntu@<monitoring-host>` → Grafana.
