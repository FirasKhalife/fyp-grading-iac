#!/usr/bin/env bash
# assay-update (assay-update.timer, about every 30 minutes): roadmap step 10, pull-based, so GitHub holds no key to
# this server.
#
# 1. Note the image each running app service uses (the ghcr.io/firaskhalife images tagged ASSAY_TAG).
# 2. docker compose pull, one service at a time.
# 3. Recreate only the services whose image changed, and wait until they are healthy (--wait).
# 4. If that fails: tag the previous images back, recreate the same services with them, and remember the failed
#    images so the next run doesn't try them again. Exit non-zero, so the unit shows as failed.
#
# Logs go to the journal: journalctl -u assay-update. The last result is in /var/lib/assay-update/last-result.
# To retry an image that was rolled back, delete /var/lib/assay-update/failed-images.
PROG=assay-update
# shellcheck source=common.sh
. /usr/local/lib/assay/common.sh

STATE=/var/lib/assay-update
FAILED="$STATE/failed-images"
mkdir -p "$STATE"
touch "$FAILED"
take_lock

result() { printf '%s %s\n' "$(date --iso-8601=seconds)" "$*" >"$STATE/last-result"; log "$*"; }

# service -> image reference, for the app services only: the images tagged ASSAY_TAG. The databases, broker, cache
# and cloudflared (third-party images pinned by digest, or derived images pinned by a version tag) are refreshed
# only by a deliberate ./deploy.sh, never in the middle of the day by this timer.
TAG="$(env_value ASSAY_TAG)"
TAG="${TAG:-latest}"
declare -A ref=() old=()
while read -r service image; do
  case "$image" in ghcr.io/firaskhalife/*:"$TAG") ref[$service]="$image" ;; esac
done < <(compose config --format json | python3 -c '
import json, sys
for name, svc in json.load(sys.stdin)["services"].items():
    if svc.get("image"):
        print(name, svc["image"])')

for service in "${!ref[@]}"; do
  id="$(compose ps -q "$service")"
  [ -n "$id" ] && old[$service]="$(docker inspect -f '{{.Image}}' "$id")"
done

# One pull per service, so an image that can't be pulled (not published yet, registry hiccup) holds back only its
# own service.
pull_failed=()
for service in "${!old[@]}"; do
  if ! compose pull --quiet "$service"; then
    pull_failed+=("$service")
    unset "old[$service]"
  fi
done
[ "${#pull_failed[@]}" = 0 ] || log "couldn't pull: ${pull_failed[*]} (kept as they are)"

changed=()
for service in "${!old[@]}"; do
  new="$(docker image inspect -f '{{.Id}}' "${ref[$service]}")"
  [ "$new" = "${old[$service]}" ] && continue
  if grep -qxF "$new" "$FAILED"; then
    # Rolled back before: keep the running image, and point the tag back at it so `up` doesn't pick the bad one.
    docker tag "${old[$service]}" "${ref[$service]}"
    log "$service: skipping ${new:7:12}, which failed before"
    continue
  fi
  changed+=("$service")
done

# A failed pull still marks the unit as failed, so it shows in `systemctl --failed`.
pull_note="" pull_rc=0
if [ "${#pull_failed[@]}" != 0 ]; then pull_note=" (couldn't pull: ${pull_failed[*]})"; pull_rc=1; fi

if [ "${#changed[@]}" = 0 ]; then
  result "$([ "$pull_rc" = 0 ] && echo OK || echo FAILED): up to date$pull_note"
  exit "$pull_rc"
fi

log "new images for: ${changed[*]}"
if compose up -d --wait --wait-timeout "$ASSAY_WAIT_TIMEOUT" --no-deps "${changed[@]}"; then
  result "OK: updated ${changed[*]}$pull_note"
  docker image prune -f >/dev/null || true
  if printf '%s\n' "${changed[@]}" | grep -qx keycloak-server; then
    flock -u 9
    /usr/local/lib/assay/keycloak-reset.sh || log "the Keycloak persona reset failed after the update"
  fi
  exit "$pull_rc"
fi

log "FAILED: ${changed[*]} didn't become healthy; rolling back to the previous images"
compose ps --format 'table {{.Service}}\t{{.Status}}' >&2 || true
for service in "${changed[@]}"; do
  docker image inspect -f '{{.Id}}' "${ref[$service]}" >>"$FAILED"
  docker tag "${old[$service]}" "${ref[$service]}"
  log "$service: back to ${old[$service]:7:12}"
done
if compose up -d --wait --wait-timeout "$ASSAY_WAIT_TIMEOUT" --no-deps "${changed[@]}"; then
  result "FAILED: update of ${changed[*]} rolled back to the previous images"
else
  result "FAILED: update of ${changed[*]} failed, and so did the rollback; see journalctl -u assay-update"
fi
exit 1
