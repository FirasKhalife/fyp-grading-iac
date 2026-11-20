#!/usr/bin/env bash
# assay-security-check: the compose repository's e2e/security.sh, on the host (it needs docker and the host's own
# network view), against the edge on 127.0.0.1, as the permanent Keycloak admin. Exit 3: the check isn't in the
# deployed compose version yet.
PROG=assay-security-check
# shellcheck source=common.sh
. /usr/local/lib/assay/common.sh

script="$ASSAY_REPO_DIR/e2e/security.sh"
if [ ! -f "$script" ]; then
  log "SKIP: e2e/security.sh isn't in the deployed compose repository version yet"
  exit 3
fi
take_lock
port="$(env_value EDGE_PORT)"
KEYCLOAK_ADMIN_USER="$(env_value KEYCLOAK_ADMIN_USER)" \
KEYCLOAK_ADMIN_PASSWORD="$(env_value KEYCLOAK_ADMIN_PASSWORD)" \
KEYCLOAK_CONTAINER="$(keycloak_container)" \
APP_ORIGIN="$(env_value PUBLIC_URL)" \
  bash "$script" "http://localhost:${port:-8080}" "http://localhost:${port:-8080}"
