# Runbook: Runtime security (CrowdSec)

The platform always runs: Traefik **rate-limiting** + security headers, **fail2ban**
(SSH), least-privilege DB users, non-root containers, prod approval gate, and CI
scanning (gitleaks/Trivy/Dependabot). **CrowdSec** (crowd-sourced IPS that bans
malicious IPs at the Traefik edge) is opt-in.

## Enable CrowdSec
1. Generate a bouncer API key (any strong random string) and set it as a GitHub
   Environment secret on the env(s) you want protected:
   ```bash
   gh secret set CROWDSEC_BOUNCER_KEY --env production \
     --repo XENTAL-PayLibre/xental-infrastructure --body "$(openssl rand -hex 32)"
   ```
2. Switch Traefik to the CrowdSec config by setting these in the env layer
   (`env/<env>.env.example`, committed — they are not secret):
   ```
   TRAEFIK_CONFIG=traefik.crowdsec.yml
   TRAEFIK_DYNAMIC_DIR=dynamic-crowdsec
   ```
3. Redeploy that environment. `deploy.sh` sees `CROWDSEC_BOUNCER_KEY` and adds the
   security overlay; Traefik loads the bouncer plugin and the `api-chain` now runs
   every request past CrowdSec.

> First enable is the one thing to validate live: Traefik downloads the bouncer
> plugin at start. Watch `docker logs xental-traefik` for plugin load + the
> `crowdsec` container becoming healthy before trusting the gate.

## Operate
```bash
docker exec xental-crowdsec cscli metrics          # parsed lines, decisions
docker exec xental-crowdsec cscli decisions list   # active bans
docker exec xental-crowdsec cscli decisions add --ip 1.2.3.4 --duration 4h
docker exec xental-crowdsec cscli decisions delete --ip 1.2.3.4
docker exec xental-crowdsec cscli alerts list
```

## Disable / roll back
Unset `TRAEFIK_CONFIG`/`TRAEFIK_DYNAMIC_DIR` (back to `traefik.yml`/`dynamic`) and
redeploy — Traefik returns to the base config; the overlay drops out when the key
is removed.

## Other layers
- **fail2ban**: `sudo fail2ban-client status sshd` on the host.
- **Rate limit**: tune `traefik/dynamic*/middlewares.yml` (`rate-limit`).
- **CI scans**: app repos → Actions → "Security scan"; Dependabot PRs weekly.
