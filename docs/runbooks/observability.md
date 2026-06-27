# Runbook: Observability

The stack (Grafana, Prometheus, Loki, Tempo, Alertmanager) runs on the monitoring
host; a Grafana Alloy agent on each app host pushes metrics, logs, and traces.

## Access Grafana (securely)
```bash
ssh -L 3000:localhost:3000 -i ~/.ssh/xental_deploy ubuntu@<monitoring-host>
# browse http://localhost:3000  (admin / GRAFANA_ADMIN_PASSWORD)
```

## View application logs
Grafana → **Explore → Loki**:
- `{job="xental-api"}` / `{job="paylibre-api"}` — service logs
- `{env="production"}` — by environment
- `{job="xental-api"} |= "ERROR"` — errors only
- Click a line's `TraceID` → jump to the trace in Tempo.
The **Xental Platform Overview** dashboard has a live logs panel.

## View metrics
Grafana → **Explore → Prometheus**: `up`, `node_load1`,
`100 - (avg by (host)(rate(node_cpu_seconds_total{mode="idle"}[5m]))*100)`,
`probe_success`, `container_memory_usage_bytes`.

## View traces
Grafana → **Explore → Tempo** → search by service name / trace ID.

## Alerts (Slack)
- Rules: `xental-observability/prometheus/alerts.yml`. Reload:
  `curl -X POST http://localhost:9090/-/reload` (via tunnel).
- Routing/Slack: `xental-observability/alertmanager/alertmanager.yml` (channel `#alerts`).
- Silence noisy alerts: Grafana → Alerting → Silences.

## If data stops flowing
1. On the app host: `docker logs xental-alloy --tail 50` (push errors?).
2. `MONITORING_HOST` set in `env/<env>.runtime.env`? If blank, Alloy isn't shipping.
3. Monitoring host SG allows 9090/3100/4317 from the app hosts' SG.
4. On the monitoring host: `docker compose ps`, `http://localhost:9090/targets`.

## Bring the stack up / update
See `xental-observability/docs/RUNBOOK.md`. One command: `docker compose up -d`.
