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

# Up to three tries: right after a deploy recreates keycloak-db, Keycloak's connection pool still holds connections
# to the old database container, and the first admin call fails with "unknown_error" (seen on 21 Nov 2026). The
# pool drops them after that failure. The script is safe to run again: it sets the same settings every time.
for attempt in 1 2 3; do
  if "$script" "$container"; then
    log "realm settings applied, personas reset (origin $ASSAY_SPA_ORIGIN)"
    exit 0
  fi
  [ "$attempt" = 3 ] || { log "attempt $attempt failed; trying again in 15 s"; sleep 15; }
done
die "the realm settings and persona reset failed three times; see: sudo assay-compose logs --tail 100 keycloak-server"
