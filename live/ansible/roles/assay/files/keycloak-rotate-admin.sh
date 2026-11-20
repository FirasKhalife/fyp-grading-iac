#!/usr/bin/env bash
# Replaces Keycloak's bootstrap master admin with a permanent one (docs/deploy-hardening.md, section 3), once.
#
#   keycloak-rotate-admin.sh <permanent-admin-username>
#
# - Already done (KEYCLOAK_ADMIN_USER in .env is the permanent admin): prints "in place", changes nothing.
# - Otherwise: creates the permanent admin with a new random password (written to .env first, so a run that stops
#   half-way resumes), gives it the master realm's admin role, checks that it can sign in, deletes the bootstrap
#   admin, and points KEYCLOAK_ADMIN_USER / KEYCLOAK_ADMIN_PASSWORD at it. Prints ROTATED.
# The passwords never leave the host's .env; they are not printed.
PROG=keycloak-rotate-admin
# shellcheck source=common.sh
. /usr/local/lib/assay/common.sh

WANT="${1:?usage: keycloak-rotate-admin.sh <permanent-admin-username>}"
CURRENT="$(env_value KEYCLOAK_ADMIN_USER)"
if [ "$CURRENT" = "$WANT" ]; then
  log "permanent admin $WANT in place"
  exit 0
fi

take_lock
KC_CONTAINER="$(keycloak_container)"
NEXT="$(env_value ASSAY_KEYCLOAK_NEXT_ADMIN_PASSWORD)"
if [ -z "$NEXT" ]; then
  NEXT="$(random_secret)"
  set_env ASSAY_KEYCLOAK_NEXT_ADMIN_PASSWORD "$NEXT"
fi

user_id() { kc get users -r master -q "username=$1" -q exact=true --fields id --format csv --noquotes; }

if kc_login "$CURRENT" "$(env_value KEYCLOAK_ADMIN_PASSWORD)"; then
  [ -n "$(user_id "$WANT")" ] || kc create users -r master -s "username=$WANT" -s enabled=true >/dev/null
  kc set-password -r master --username "$WANT" --new-password "$NEXT"
  kc add-roles -r master --uusername "$WANT" --rolename admin
  log "created $WANT"
elif ! kc_login "$WANT" "$NEXT"; then
  die "can sign in neither as $CURRENT nor as $WANT"
fi

kc_login "$WANT" "$NEXT" || die "$WANT can't sign in; the bootstrap admin is kept"
old="$(user_id "$CURRENT")"
if [ -n "$old" ]; then
  kc delete "users/$old" -r master
  log "deleted the bootstrap admin $CURRENT"
fi

set_env KEYCLOAK_ADMIN_USER "$WANT"
set_env KEYCLOAK_ADMIN_PASSWORD "$NEXT"
unset_env ASSAY_KEYCLOAK_NEXT_ADMIN_PASSWORD
echo ROTATED
