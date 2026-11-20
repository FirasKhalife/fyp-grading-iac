#!/usr/bin/env bash
# assay-keycloak-reset (assay-keycloak-reset.timer, nightly, and after a deploy or a Keycloak update): runs the
# compose repository's scripts/keycloak-reset-personas.sh against the production Keycloak, as the permanent admin,
# with ASSAY_SPA_ORIGIN set to the public URL.
PROG=assay-keycloak-reset
# shellcheck source=common.sh
. /usr/local/lib/assay/common.sh

take_lock
script="$ASSAY_REPO_DIR/scripts/keycloak-reset-personas.sh"
[ -f "$script" ] || die "$script is missing"
container="$(keycloak_container)"

KEYCLOAK_ADMIN_USER="$(env_value KEYCLOAK_ADMIN_USER)"
KEYCLOAK_ADMIN_PASSWORD="$(env_value KEYCLOAK_ADMIN_PASSWORD)"
ASSAY_SPA_ORIGIN="$(env_value PUBLIC_URL)"
export KEYCLOAK_ADMIN_USER KEYCLOAK_ADMIN_PASSWORD ASSAY_SPA_ORIGIN

# The script's kcadm.sh calls keep their session in the container's home directory, which is read-only in the
# production container. Until the script passes --config itself, a `docker` shim adds --config /tmp/kcadm.config to
# them. (Listed as a change for the compose repository in live/README.md.)
if ! grep -q -- '--config' "$script"; then
  shim="$(mktemp -d)"
  trap 'rm -rf "$shim"' EXIT
  cat >"$shim/docker" <<'SHIM'
#!/usr/bin/env bash
if [ "${1:-}" = exec ]; then
  for arg in "$@"; do
    [ "$arg" = /opt/keycloak/bin/kcadm.sh ] && exec /usr/bin/docker "$@" --config /tmp/kcadm.config
  done
fi
exec /usr/bin/docker "$@"
SHIM
  chmod 0755 "$shim/docker"
  PATH="$shim:$PATH"
fi

"$script" "$container"
log "realm settings applied, personas reset (origin $ASSAY_SPA_ORIGIN)"
