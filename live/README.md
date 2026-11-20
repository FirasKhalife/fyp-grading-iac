# live/: the real deployment (Netcup + Cloudflare)

The AWS code next to this folder ([`terraform/`](../terraform/), [`cdk/`](../cdk/)) is a reference that has never
been applied. This folder is the deployment that actually runs the demo, at **https://assay.firaskhalife.dev**:

```
visitor ── HTTPS ──► Cloudflare (TLS, WAF, rate limit) ══ tunnel ══► cloudflared ──► edge:8080 ──► app, /api, /realms/assay
                                                         (outbound            one Netcup VPS 1000: 8 GB, 4 vCPU,
                                                          from the server)    Debian 13/12 or Ubuntu 24.04, Docker
```

- **The server opens no web port.** cloudflared, in the prod compose's `tunnel` profile, dials out to Cloudflare. The
  firewall allows only SSH in, by key, for the deploy user, and fail2ban watches it. Nobody signs in by hand:
  Ansible and `verify.sh` use the key.
- **What runs** is `fyp-grading-docker-compose/docker-compose/prod/compose.yml` and `edge.nginx.conf`, unchanged,
  with the public `ghcr.io/firaskhalife/fyp-grading-*` images. The Keycloak admin console, Grafana, RabbitMQ's UI,
  Eureka and the actuators are not reachable from outside: the edge answers 404.
- **Updates are pulled, not pushed.** A timer on the server pulls new images about every 30 minutes, recreates only
  what changed, and rolls back if a new image doesn't become healthy. GitHub has no key to the server.

| Folder / file | What |
| --- | --- |
| [`tofu/`](tofu/) | OpenTofu, Cloudflare provider: the tunnel and its ingress, the DNS record, a rate limit on Keycloak's token endpoint, HSTS and TLS settings |
| [`ansible/`](ansible/) | Hardening (deploy user, SSH, ufw, fail2ban, unattended upgrades, swap, time), Docker CE, the stack, Keycloak, the timers |
| [`tools.sh`](tools.sh) | Installs pinned OpenTofu, ShellCheck, Ansible and ansible-lint into `~/.local` (no sudo) |
| [`tofu.sh`](tofu.sh) | Runs `tofu` with the Cloudflare credentials from `~/.config/assay/cloudflare.env` |
| [`deploy.sh`](deploy.sh) | Runs a playbook; hands the tunnel token from the OpenTofu state to Ansible without printing it |
| [`verify.sh`](verify.sh) | Checks the live demo from outside, and the server-side checks over SSH |
| [`check.sh`](check.sh) | Offline checks: `tofu fmt`/`validate`, `ansible-lint`, `--syntax-check`, ShellCheck (CI runs it too) |
| [`../.github/workflows/uptime.yml`](../.github/workflows/uptime.yml) | Every 15 minutes: landing page and token endpoint; a failure emails you |

Everything below runs in **WSL Ubuntu**, from this folder. Nothing in it costs money except the server itself.

## 1. Before you start (by hand)

1. **The server.** Order a Netcup VPS 1000 G12 (or the current equivalent: 8 GB, 4 vCPU, amd64). Netcup has no
   ordering API, so this is the one manual purchase. In the server control panel, install **Debian 13** (Debian 12 and
   Ubuntu 24.04 work too) and, if the installer offers it, paste the contents of `~/.ssh/assay_netcup.pub` as root's
   SSH key. Note the server's IPv4 address.

2. **A Cloudflare API token.** Cloudflare dashboard > My Profile > API Tokens > Create Token > Custom token.
   These permissions are enough on the free plan, and nothing more is needed:

   | Scope | Permission | Access | Used for |
   | --- | --- | --- | --- |
   | Account | Cloudflare Tunnel | Edit | create the tunnel, its ingress, read its token |
   | Zone | Zone | Read | look up `firaskhalife.dev` |
   | Zone | DNS | Edit | the `assay` CNAME |
   | Zone | Zone Settings | Edit | always HTTPS, min TLS 1.2, TLS 1.3, automatic HTTPS rewrites |
   | Zone | Zone WAF | Edit | the rate-limiting rule (`http_ratelimit` phase) |
   | Zone | Transform Rules | Edit | the HSTS response header (`http_response_headers_transform` phase) |

   Account resources: *Include > your account*. Zone resources: *Include > Specific zone > firaskhalife.dev*.
   Optionally restrict it to your IP and give it an expiry date. Copy the token once; Cloudflare doesn't show it again.
   Your **account ID** is on the zone's Overview page (right column).

3. **The local credentials file.** In WSL (the passphrase encrypts the OpenTofu state; keep a copy in your password
   manager, losing it means losing the state):

   ```bash
   mkdir -p ~/.config/assay && chmod 700 ~/.config/assay
   cat > ~/.config/assay/cloudflare.env <<'EOF'
   CLOUDFLARE_API_TOKEN=paste-the-token-here
   TF_VAR_cloudflare_account_id=paste-the-account-id-here
   TF_VAR_state_passphrase=paste-a-long-random-passphrase-here
   EOF
   chmod 600 ~/.config/assay/cloudflare.env
   ```

   (`openssl rand -base64 32` makes a passphrase.) The scripts read this file; they never print what is in it.

4. **The tools**, once (OpenTofu 1.13, ShellCheck, uv with Python 3.13, ansible-core 2.22, ansible-lint, the Ansible
   collections; all pinned and checksum-verified, installed into `~/.local/bin`):

   ```bash
   cd "/mnt/c/src/0. personal/fyp-grading/fyp-grading-iac/live"
   ./tools.sh
   ./check.sh      # optional: the offline checks
   ```

## 2. Cloudflare: `tofu apply`

```bash
./tofu.sh init
./tofu.sh plan      # read it: a tunnel, its config, one DNS record, two rulesets, four zone settings
./tofu.sh apply
```

The state (`tofu/terraform.tfstate`) stays on this machine, git-ignored and encrypted with your passphrase. It holds
the tunnel's secret. `./tofu.sh output` shows the tunnel ID and URL; the token output is sensitive and is only read
by `deploy.sh`.

**Zone-wide settings.** Always-HTTPS, minimum TLS 1.2, TLS 1.3 and automatic HTTPS rewrites apply to every hostname
in `firaskhalife.dev`, not only `assay`. That is normally what you want; set `manage_zone_settings = false` (in a
git-ignored `tofu/terraform.tfvars`) to leave them alone. HSTS is set for `assay.firaskhalife.dev` only, without
`includeSubDomains` or `preload`. Brotli needs nothing: Cloudflare compresses with it on every plan and retired the
setting. The free plan's managed WAF ruleset is on by default and stays as Cloudflare manages it.

## 3. The server: Ansible

```bash
cp ansible/inventory.example.yml ansible/inventory.yml   # git-ignored; put the server's IPv4 in it
./deploy.sh bootstrap      # once, as root: creates the deploy user with your key
                           # (root has a password, no key? add -k; needs: sudo apt install sshpass)
./deploy.sh                # everything else; safe to run again at any time
```

`bootstrap` signs in as root, makes sure Python is there, and creates `deploy` (key only, no password, passwordless
sudo). From then on everything signs in as `deploy`, and the first `./deploy.sh` turns root login off, so bootstrap
can't (and needn't) run again. If the server is ever reinstalled, its host key changes: `ssh-keygen -R <ip>` first.

What `./deploy.sh` (`site.yml`) does, in order:

1. **Hardening** (`roles/base`): the deploy user; sshd with keys only, no root, no passwords, `AllowUsers deploy`;
   ufw allowing only 22/tcp in (rate-limited); fail2ban on sshd (journal backend, bans through ufw); unattended
   upgrades with an automatic reboot at 04:30 when one is needed; a 2 GB swapfile with low swappiness; time zone
   Europe/Paris; NTP (systemd-timesyncd, or chrony if the image has it); a 500 MB cap on the journal.
2. **Docker** (`roles/docker`): Docker CE and the compose plugin from Docker's apt repository, with json-file log
   rotation (10 MB × 3) and `live-restore`, so restarting dockerd doesn't stop the containers.
3. **The stack** (`roles/assay`):
   - clones the public compose repository to `/opt/assay/fyp-grading-docker-compose` at `assay_compose_version`
     (`group_vars/assay.yml`, default `master`; a commit SHA makes a deploy repeatable), so the host runs that
     repository's own `prod/compose.yml`, `edge.nginx.conf`, scripts and checks;
   - creates `docker-compose/prod/.env` **only if it is missing**: 32-character random secrets, like `run-demo.sh`.
     It is never regenerated (the databases were initialised with those passwords). `PUBLIC_URL`, `ASSAY_TAG` and
     `TUNNEL_TOKEN` are kept in line on every run. Nothing here sets the services' environment by hand: values
     derived from `PUBLIC_URL`, such as `AUTH_ISSUER_URI=${PUBLIC_URL}/realms/assay` (the token issuer the gateway
     and services accept), come from `prod/compose.yml` itself;
   - `docker compose --profile tunnel up -d --wait`.
4. **Keycloak** (docs/deploy-hardening.md, section 3): on the first deploy, a permanent master-realm admin
   (`assay-admin`) replaces the bootstrap one, with a random password that exists only in the host's `.env`;
   `KEYCLOAK_ADMIN_USER` / `KEYCLOAK_ADMIN_PASSWORD` then point at it. Then `scripts/keycloak-reset-personas.sh` runs
   with `ASSAY_SPA_ORIGIN` set to the public URL. No 2FA on the admin: there is no console to use it in, only
   `kcadm.sh` through `docker exec` on the host.
5. **Timers**: `assay-keycloak-reset.timer` (nightly at 00:05, after the midnight purge) and `assay-update.timer`.

**The midnight purge is not scheduled here.** admin-service already does it: `DemoService.purgeAll()` runs at
`0 0 0 * * *` in Europe/Paris (`@Scheduled`, scheduling on in `ClockConfig`), and on start it purges copies from
before the last midnight if it was down then. The other services purge their own parts.

### Updates (pull-based)

`assay-update.timer` runs `/usr/local/lib/assay/update.sh` every 30 minutes (± 3):

1. notes the image every running app service uses (the `ghcr.io/firaskhalife/*` images tagged `ASSAY_TAG`), then
   pulls them one service at a time, so an image that can't be pulled holds back only its own service;
2. recreates **only** the services whose image changed, with `--wait`;
3. if one doesn't become healthy: tags the previous images back, recreates the same services with them, records the
   failed image IDs in `/var/lib/assay-update/failed-images` (so the next run doesn't retry them), logs it, and the
   unit shows as failed. After a Keycloak update it also re-runs the persona reset.

On the server: `journalctl -u assay-update`, `cat /var/lib/assay-update/last-result`. The timer never touches the
databases, RabbitMQ, Redis or cloudflared: their images are pinned by digest or (the derived Postgres and Mongo
images) by a version tag, and they change only with `./deploy.sh`, which pulls every image and recreates only those
that changed. Compose file changes
(Dependabot bumps, edge config) are never pulled automatically: they go live when you run `./deploy.sh`. Pin
`assay_image_tag` to a commit's short SHA to freeze the images.

### Backups

Only one thing on the server matters: the host's `.env`. Everything else is either in git (compose files, realm,
config), in GHCR (images), in the OpenTofu state (the tunnel) or demo data, which every visitor gets fresh from the
seed and which is purged at midnight anyway.

Even the `.env` can be lost safely: run `sudo assay-compose down --volumes` on the server (or reinstall it), delete
nothing else, and `./deploy.sh` makes a new one with new secrets and a fresh seed. A backup only saves you that.
To keep an encrypted copy anyway:

```bash
openssl rand -base64 32 > ~/.config/assay/vault-pass && chmod 600 ~/.config/assay/vault-pass   # once; also in your password manager
./deploy.sh backup-env     # writes ~/.config/assay/backups/netcup-env-<date>.vault (ansible-vault, AES-256)
ansible-vault view --vault-password-file ~/.config/assay/vault-pass ~/.config/assay/backups/netcup-env-<date>.vault
```

## 4. Check it: `verify.sh`

```bash
./verify.sh
```

1. **edge**: the landing page, `http://` → `https://`, the HSTS header, a persona sign-in, and 404 from outside for
   `/admin`, `/admin/master/console/`, `/realms/master`, `/actuator`, `/actuator/env`, `/eureka`, `/eureka/apps`;
2. **ports**: from your machine, only 22 answers on the server's address;
3. **smoke**: the compose repo's `e2e/smoke.sh` against the public URL;
4. **api**: `e2e/api-checks.py` against the public URL;
5. **security**: `e2e/security.sh`, on the server over SSH (it needs docker and the server's own view of its ports);
6. **browser**: the frontend's real-stack Playwright suite with `ASSAY_BASE_URL` set to the public URL.

The suites make a demo copy per test, and the gateway allows one a minute per visitor, so `verify.sh` lifts that
limit on the server for the run and puts it back at the end, also when a check fails (`--keep-copy-limit` skips
that; the gateway restarts twice, 10–20 s each). `--skip-host` runs only what needs no SSH, `--skip-playwright`
skips step 6. Steps 3 and 4 use your local checkout of `fyp-grading-docker-compose`; step 5 uses the server's
(`assay_compose_version`). A step whose script isn't there yet is reported as skipped.

For step 6, once, in a Linux checkout of the frontend (WSL's own Node, not the Windows one):

```bash
cd ../../fyp-grading-frontend && npm ci && npx playwright install --with-deps chromium
```

(`--with-deps` asks for sudo to install Chromium's system libraries.) A `node_modules` installed from Windows has
no Linux browsers, so run `npm ci` from WSL; set `ASSAY_FRONTEND_REPO` if that checkout is elsewhere.

## 5. Uptime check

[`uptime.yml`](../.github/workflows/uptime.yml) runs every 15 minutes on GitHub: the landing page must answer with the
app, and the token endpoint must sign in a demo persona. A failed run makes GitHub email whoever last changed its
schedule. It is off until you set the repository variable **`ASSAY_UPTIME_ENABLED` = `true`** (Settings > Secrets
and variables > Actions > Variables), so it doesn't fail every 15 minutes before the server exists. GitHub pauses
scheduled workflows after 60 days without activity in a public repository, and emails before it does.

## On the server, if you ever need it

```bash
sudo assay-compose ps                  # docker compose for the stack, from anywhere
sudo assay-compose logs -f --tail 100 api-gateway
sudo assay-update                      # look for new images now
sudo assay-keycloak-reset              # reapply the realm settings, reset the personas
sudo assay-copy-limit show | lift | restore
sudo assay-security-check
systemctl list-timers 'assay-*'
```

## Troubleshooting

- **`tofu apply`: a ruleset "already exists".** A zone has one entry-point ruleset per phase. If the dashboard made one
  (a rate-limiting rule or a response header rule), import it, then apply (the apply replaces its rules with these):
  `./tofu.sh import cloudflare_ruleset.rate_limit 'zones/<zone-id>/<ruleset-id>'` (and `.response_headers`). The
  IDs are in the dashboard or `GET /zones/<zone-id>/rulesets`.
- **The tunnel stays down** (`cloudflared` unhealthy, so `--wait` fails): the token is wrong or the tunnel was deleted.
  `./tofu.sh apply` recreates a missing tunnel, and `./deploy.sh` writes the new token to the host.
- **Lost the state?** Without it OpenTofu doesn't know the tunnel exists. Either delete the tunnel and the
  `assay` DNS record in the dashboard and apply again (then `./deploy.sh`), or import both
  (`cloudflare_zero_trust_tunnel_cloudflared.assay`, `cloudflare_dns_record.assay`).
- **Locked out of SSH.** Netcup's control panel has a VNC console; root has no password there unless you set one in
  the installer. Reinstalling the server and running steps 3–4 again rebuilds everything.

## Compose repository prerequisites

Everything this deployment needs from `fyp-grading-docker-compose` is on its `master` (merged 20 Nov 2026):

- `scripts/keycloak-reset-personas.sh` passes `--config` to kcadm, since the production Keycloak's root is read-only.
- The derived Postgres and MongoDB images are published, public and pinned by digest.
- `e2e/api-checks.py` and `e2e/security.sh` are there for `verify.sh`.
- The gateway and services check the token issuer and client (`AUTH_ISSUER_URI`, set in `prod/compose.yml` from
  `PUBLIC_URL`).

Master was checked with the published `latest` images: smoke 27/27, API checks 64/64, security 37/37.
