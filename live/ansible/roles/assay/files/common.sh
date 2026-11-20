# shellcheck shell=bash
# Shared by the Assay host scripts (installed by Ansible in /usr/local/lib/assay). Sourced, not run.
set -euo pipefail

# shellcheck source=/dev/null
. /etc/default/assay # ASSAY_REPO_DIR, ASSAY_PROD_DIR, ASSAY_WAIT_TIMEOUT
ENV_FILE="$ASSAY_PROD_DIR/.env"
PROG="${PROG:-$(basename "$0")}"

log() { printf '%s: %s\n' "$PROG" "$*"; }
die() { printf '%s: %s\n' "$PROG" "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run as root (sudo)"

# The production stack, always with the tunnel profile, so cloudflared is part of every pull and up.
compose() {
  docker compose --project-directory "$ASSAY_PROD_DIR" -f "$ASSAY_PROD_DIR/compose.yml" --profile tunnel "$@"
}

# One job at a time: the update timer, the persona reset, the copy-limit switch and the checks.
take_lock() {
  exec 9>/run/lock/assay.lock
  flock -w 1800 9 || die "another Assay job still holds /run/lock/assay.lock"
}

# .env helpers. Every value written here is letters and digits only.
env_value() { sed -n "s|^$1=||p" "$ENV_FILE" | tail -n 1; }
set_env() {
  if grep -q "^$1=" "$ENV_FILE"; then
    sed -i "s|^$1=.*|$1=$2|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$1" "$2" >>"$ENV_FILE"
  fi
}
unset_env() { sed -i "/^$1=/d" "$ENV_FILE"; }
random_secret() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 || true; }

keycloak_container() {
  local id
  id="$(compose ps -q keycloak-server)"
  [ -n "$id" ] || die "the keycloak-server container isn't running"
  printf '%s' "$id"
}

# kcadm.sh in the Keycloak container. Its root filesystem is read-only, so the session file goes to /tmp (a tmpfs).
kc() { docker exec "$KC_CONTAINER" /opt/keycloak/bin/kcadm.sh "$@" --config /tmp/kcadm.config; }
kc_login() {
  kc config credentials --server http://localhost:8080 --realm master --user "$1" --password "$2" >/dev/null 2>&1
}
