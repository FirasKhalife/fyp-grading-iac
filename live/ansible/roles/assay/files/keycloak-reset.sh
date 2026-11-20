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

"$script" "$container"
log "realm settings applied, personas reset (origin $ASSAY_SPA_ORIGIN)"
