# Platform runbooks

Operational playbooks for the Xental platform. Start here.

| Runbook | When to use |
|---|---|
| [deploy.md](deploy.md) | Release a service to staging/production |
| [rollback.md](rollback.md) | A release is bad; revert it |
| [incident-response.md](incident-response.md) | A Slack alert fired / a service is down |
| [host-lifecycle.md](host-lifecycle.md) | Stop/start/restart/replace/resize a host |
| [secret-rotation.md](secret-rotation.md) | Rotate DB / GHCR / SSH / Slack secrets |
| [backup-restore.md](backup-restore.md) | Back up or restore a database |
| [observability.md](observability.md) | View metrics, logs, traces; manage alerts |

Reference docs: [../ENVIRONMENT.md](../ENVIRONMENT.md) (config/secrets model),
[../../README.md](../../README.md) (architecture), [../../RUNBOOK.md](../../RUNBOOK.md)
(first-time bring-up).

## Platform at a glance
- **Hosts:** staging + production EC2 (Docker Compose), one monitoring host.
- **Registry:** GHCR `ghcr.io/xental-paylibre/*`.
- **Deploy:** push to `staging`/`main` → build → GHCR → SSH deploy (prod gated by approval).
- **Rollback:** auto on failed health check; or the Rollback workflow.
- **Observability:** Grafana/Prometheus/Loki/Tempo on the monitoring host; Alloy on app hosts.
- **Alerts:** Alertmanager → Slack `#alerts`.
