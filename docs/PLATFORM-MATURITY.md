# Platform maturity — what's done, what's left

Honest assessment of the platform against "proper platform engineering," with a
prioritised gap list. P0 = do before real production traffic; P1 = production
hardening; P2 = scale & org maturity.

## In place today
- **IaC**: Terraform for hosts, security groups, EIPs, SSH key, monitoring host.
- **CI/CD**: build → GHCR → SSH deploy; health-check **auto-rollback**; prod
  **approval gate**; immutable `sha-` tags; git-pinned versions.
- **Config/secrets**: GitHub Environment secrets, layered env files, no hardcoding.
- **Observability**: metrics + logs + traces (Prometheus/Loki/Tempo), Grafana
  dashboards, **Slack alerting**; one-command stack.
- **Security**: CI scanning (gitleaks/Trivy/Dependabot); runtime rate-limit,
  fail2ban, **CrowdSec** (opt-in); non-root containers; least-privilege DB users.
- **Backups**: nightly `pg_dump` (local + optional S3).
- **Runbooks**: deploy, rollback, incident, host lifecycle, secrets, backup, security.

## P0 — before serving real production traffic
1. **Domain + DNS + TLS** — currently placeholder certs; wire the real domain so
   Let's Encrypt issues valid certs.
2. **Terraform remote state + locking** — move state to **S3 + DynamoDB lock**
   (today it's local on one laptop = risk of loss/corruption/conflicts).
3. **Durable database** — prod Postgres is a single container on the app host
   (SPOF, no failover, no PITR). Move prod to **RDS (Multi-AZ)**; keep the
   container only for dev/staging. Until then: verified **offsite backups +
   tested restore**.
4. **DB migrations** — adopt EF Core migrations with an expand/contract workflow,
   applied safely as a deploy step (not ad-hoc).
5. **Automated tests in CI** — unit + integration tests and a **smoke test gate**
   before prod deploy (today the pipeline builds but doesn't test).

## P1 — production hardening
6. **High availability** — ≥2 app hosts behind an **ALB**; app hosts in **private
   subnets** (not public); inbound only via ALB; SSH via **SSM/bastion** only;
   tighten SGs. Removes the single-host SPOF.
7. **Zero-downtime deploys** — rolling/blue-green via the ALB (today `compose up`
   has a brief restart).
8. **Observability durability** — S3-backed Loki/Tempo (+ Mimir/Thanos) for longer
   retention and no data loss if the monitoring host dies; back up Grafana.
9. **On-call & SLOs** — define SLOs/error budgets; route critical alerts to
   **PagerDuty/Opsgenie** (Slack alone isn't an on-call system).
10. **Supply chain** — sign images (**cosign**), generate **SBOMs**, and only
    deploy signed images (policy). Today we scan but don't sign/enforce.
11. **Terraform CI + policy-as-code** — `plan` on PRs, drift detection, and
    OPA/conftest checks; no manual `apply` from laptops.
12. **Secrets maturity** — rotation automation; consider AWS Secrets Manager /
    Vault for central management + audit (GitHub secrets have no rotation/audit).
13. **Edge WAF** — managed WAF (AWS WAF / Cloudflare) in front of Traefik in
    addition to CrowdSec.

## P2 — scale & org maturity
14. **Orchestration / autoscaling** — if load grows, move to **ECS/EKS** with
    horizontal autoscaling (Compose-on-VM has a ceiling).
15. **Preview environments** — ephemeral per-PR environments for review.
16. **Cost management** — budgets + alerts, rightsizing, scheduled start/stop
    (we stop manually today), savings plans.
17. **Disaster recovery** — cross-region backups, documented **RTO/RPO**, and
    periodic DR drills.
18. **Identity & access** — SSO/RBAC for AWS, GitHub, and Grafana; audit logging
    (CloudTrail); per-engineer access instead of a shared key.
19. **API gateway** — quotas, auth, API keys if you expose public APIs broadly.

## Suggested order
TLS/DNS → remote TF state → RDS + migrations → CI tests/smoke gate → HA (ALB +
private subnets) → zero-downtime → on-call/SLOs → supply-chain signing → the rest.
