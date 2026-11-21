#!/usr/bin/env bash
# Checks the deployed demo from outside, through Cloudflare, plus the checks that must run on the server itself.
#
#   live/verify.sh [--skip-playwright] [--skip-host] [--keep-copy-limit]
#
# 1. edge      the landing page, HTTPS redirect and HSTS; a persona token the API accepts, and an admin-cli token
#              it rejects with 401; /admin, /realms/master, /actuator and /eureka answer 404 from outside
# 2. ports     from this machine, only 22 answers on the server's address (needs live/ansible/inventory.yml)
# 3. smoke     the compose repo's e2e/smoke.sh against the public URL
# 4. api       the compose repo's e2e/api-checks.py against the public URL (skipped until it is in the repo)
# 5. security  the compose repo's e2e/security.sh, on the server over SSH (it needs docker there)
# 6. browser   the frontend's real-stack Playwright suite with ASSAY_BASE_URL set to the public URL
#
# The suites make a demo copy per test, and the gateway allows one copy a minute per visitor. So, unless
# --keep-copy-limit, the limit is lifted on the server for the run and put back at the end, even on failure (the
# gateway restarts twice, about 10-20 s each). --skip-host skips 2, 5 and the limit switch (no SSH at all).
#
# Env: ASSAY_URL (default https://assay.firaskhalife.dev), ASSAY_COMPOSE_REPO and ASSAY_FRONTEND_REPO (default the
# sibling checkouts next to this repository).
# Needs: bash, curl, python3 (3.9+), ssh, and for 6 Node 20+ with the frontend's dependencies and Playwright's
# Chromium installed (live/README.md, step 5).
set -uo pipefail

LIVE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
URL="${ASSAY_URL:-https://assay.firaskhalife.dev}"
URL="${URL%/}"
WORKSPACE="$(cd "$LIVE/../.." && pwd)"
COMPOSE_REPO="${ASSAY_COMPOSE_REPO:-$WORKSPACE/fyp-grading-docker-compose}"
FRONTEND_REPO="${ASSAY_FRONTEND_REPO:-$WORKSPACE/fyp-grading-frontend}"
SSH_KEY="${ASSAY_SSH_KEY:-$HOME/.ssh/assay_netcup}"
PASSWORD="${DEMO_PASSWORD:-assay-demo}"

playwright=1 host=1 lift=1
for arg in "$@"; do
  case "$arg" in
    --skip-playwright) playwright=0 ;;
    --skip-host) host=0 ;;
    --keep-copy-limit) lift=0 ;;
    -h | --help) sed -n '2,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "verify.sh: unknown option $arg" >&2; exit 2 ;;
  esac
done
[ "$host" = 1 ] || lift=0

declare -a summary=()
failed=0
step() { printf '\n== %s\n' "$1"; }
record() { # record <step> <exit code>
  case "$2" in
    0) summary+=("ok    $1") ;;
    skip) summary+=("skip  $1") ;;
    *) summary+=("FAIL  $1"); failed=1 ;;
  esac
}

# ---------------------------------------------------------------- the server, over SSH
SSH_HOST="" SSH_USER=""
SSH_CTL="$(mktemp -u /tmp/assay-verify-ssh.XXXXXX)"
if [ "$host" = 1 ]; then
  inv="$LIVE/ansible/inventory.yml"
  [ -f "$inv" ] || { echo "verify.sh: $inv is missing (or use --skip-host)" >&2; exit 2; }
  read -r SSH_HOST SSH_USER < <(ANSIBLE_CONFIG="$LIVE/ansible/ansible.cfg" ansible-inventory -i "$inv" --list | python3 -c '
import json, sys
d = json.load(sys.stdin)
name = d["assay"]["hosts"][0]
v = d["_meta"]["hostvars"][name]
print(v.get("ansible_host", name), v.get("base_deploy_user", "deploy"))')
  [ -n "$SSH_HOST" ] || { echo "verify.sh: no host in $inv" >&2; exit 2; }
fi
# One SSH connection for the whole run (ufw rate-limits new SSH connections).
remote() {
  ssh -i "$SSH_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o BatchMode=yes \
    -o ControlMaster=auto -o ControlPath="$SSH_CTL" -o ControlPersist=120 "$SSH_USER@$SSH_HOST" "$@"
}

restore_limit() {
  if [ "$lift" = 1 ]; then
    step "putting the demo copy limit back"
    remote sudo assay-copy-limit restore || echo "verify.sh: couldn't restore the copy limit; run: live/deploy.sh (or assay-copy-limit restore on the server)" >&2
    lift=0
  fi
  [ "$host" = 1 ] && ssh -o ControlPath="$SSH_CTL" -O exit "$SSH_USER@$SSH_HOST" 2>/dev/null
  rm -rf "$TMP"
}
TMP="$(mktemp -d)"
trap restore_limit EXIT
trap 'exit 130' INT TERM

echo "Verifying $URL"

# ---------------------------------------------------------------- 1. edge
step "1. edge: landing page, HTTPS, closed paths"
(
  bad=0
  check() { # check <description> <command...>: runs the command, prints ok or FAIL
    local what="$1"; shift
    if "$@"; then echo "  ok   $what"; else echo "  FAIL $what"; bad=1; fi
  }
  code="$(curl -s -o "$TMP/index" -D "$TMP/headers" -w '%{http_code}' "$URL/")"
  # shellcheck disable=SC2329 # called through check
  landing_ok() { [ "$code" = 200 ] && grep -q '<title>Assay</title>' "$TMP/index"; }
  # shellcheck disable=SC2329 # called through check
  redirect_ok() { [[ "$redirect" =~ ^30[178]\ https:// ]]; }
  check "landing page ($code)" landing_ok
  check "HSTS header" grep -qi '^strict-transport-security: max-age=' "$TMP/headers"
  redirect="$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "http://${URL#https://}/")"
  check "http:// redirects to https:// ($redirect)" redirect_ok
  tok="$(curl -s "$URL/realms/assay/protocol/openid-connect/token" -d grant_type=password -d client_id=assay-spa \
    -d username=jane.smith -d "password=$PASSWORD" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null)"
  check "persona sign-in at the token endpoint" test -n "$tok"
  # Without a demo copy the API answers 400 demo-session-required, and it only gets that far once the token is
  # accepted (a rejected token gets 401 first).
  code="$(curl -s -o "$TMP/api" -w '%{http_code}' -H "Authorization: Bearer $tok" "$URL/api/notifications")"
  check "the persona's token is accepted by the API ($code)" grep -q demo-session-required "$TMP/api"
  # The services accept only tokens issued for the app's own clients (AUTH_ISSUER_URI and the client check): a
  # token from another client of the same realm, such as Keycloak's built-in admin-cli, must get 401. If the realm
  # doesn't issue admin-cli a token at all, there is nothing to reject.
  other="$(curl -s "$URL/realms/assay/protocol/openid-connect/token" -d grant_type=password -d client_id=admin-cli \
    -d username=jane.smith -d "password=$PASSWORD" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null)"
  if [ -n "$other" ]; then
    code="$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $other" "$URL/api/notifications")"
    check "an admin-cli token is rejected by the API ($code)" test "$code" = 401
  else
    echo "  ok   admin-cli gets no token in the assay realm (nothing to reject)"
  fi
  for path in /admin /admin/ /admin/master/console/ /realms/master /realms/master/ \
    /realms/master/protocol/openid-connect/token /actuator /actuator/health /actuator/env /eureka /eureka/apps; do
    code="$(curl -s -o /dev/null -w '%{http_code}' "$URL$path")"
    check "$path answers 404 ($code)" test "$code" = 404
  done
  exit "$bad"
)
record "edge" $?

# ---------------------------------------------------------------- 2. ports
if [ "$host" = 1 ]; then
  step "2. ports: only SSH answers on $SSH_HOST"
  (
    bad=0
    if timeout 5 bash -c "exec 3<>/dev/tcp/$SSH_HOST/22" 2>/dev/null; then echo "  ok   22 open (SSH)"; else echo "  FAIL 22 doesn't answer"; bad=1; fi
    for p in 80 443 2000 5432 5672 6379 7080 8071 8080 8761 9000 9191 9192 15672 27017; do
      if timeout 3 bash -c "exec 3<>/dev/tcp/$SSH_HOST/$p" 2>/dev/null; then echo "  FAIL $p is open"; bad=1; else echo "  ok   $p closed"; fi
    done
    exit "$bad"
  )
  record "ports" $?
else
  record "ports (--skip-host)" skip
fi

# ---------------------------------------------------------------- lift the copy limit
if [ "$lift" = 1 ]; then
  step "lifting the demo copy limit for the test run"
  remote sudo assay-copy-limit lift || { echo "verify.sh: couldn't lift the copy limit" >&2; lift=0; }
fi

# ---------------------------------------------------------------- 3. smoke
step "3. smoke: e2e/smoke.sh"
if [ -f "$COMPOSE_REPO/e2e/smoke.sh" ]; then
  APP_ORIGIN="$URL" bash "$COMPOSE_REPO/e2e/smoke.sh" "$URL" "$URL"
  record "smoke" $?
else
  echo "  $COMPOSE_REPO/e2e/smoke.sh not found (set ASSAY_COMPOSE_REPO)"
  record "smoke" 1
fi

# ---------------------------------------------------------------- 4. api
step "4. api: e2e/api-checks.py"
if [ -f "$COMPOSE_REPO/e2e/api-checks.py" ]; then
  python3 "$COMPOSE_REPO/e2e/api-checks.py" "$URL" "$URL"
  record "api" $?
else
  echo "  skipped: e2e/api-checks.py isn't in $COMPOSE_REPO yet"
  record "api (not in the compose repo yet)" skip
fi

# ---------------------------------------------------------------- 5. security
if [ "$host" = 1 ]; then
  step "5. security: e2e/security.sh on the server"
  remote sudo assay-security-check
  rc=$?
  if [ "$rc" = 3 ]; then record "security (not in the deployed compose version yet)" skip; else record "security" "$rc"; fi
else
  record "security (--skip-host)" skip
fi

# ---------------------------------------------------------------- 6. browser
if [ "$playwright" = 1 ]; then
  step "6. browser: Playwright real-stack suite"
  cli="$FRONTEND_REPO/node_modules/@playwright/test/cli.js"
  if [ -f "$cli" ] && [ -f "$FRONTEND_REPO/playwright.real.config.ts" ]; then
    (cd "$FRONTEND_REPO" && ASSAY_BASE_URL="$URL" node "$cli" test -c playwright.real.config.ts)
    record "browser" $?
  else
    echo "  $cli not found: run npm ci and npx playwright install chromium in $FRONTEND_REPO (README, step 5)"
    record "browser" 1
  fi
else
  record "browser (--skip-playwright)" skip
fi

restore_limit
printf '\n== summary for %s\n' "$URL"
printf '  %s\n' "${summary[@]}"
exit "$failed"
