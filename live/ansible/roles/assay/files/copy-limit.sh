#!/usr/bin/env bash
# assay-copy-limit lift | restore | show
#
# The gateway lets each visitor make one demo copy a minute. The test suites make a copy per test, so live/verify.sh
# lifts the limit for its run (600 a second, as the Playwright suite expects) and restores it afterwards. Each switch
# recreates the gateway, so the API is away for about 10-20 seconds.
PROG=assay-copy-limit
# shellcheck source=common.sh
. /usr/local/lib/assay/common.sh

case "${1:-show}" in
  lift) take_lock; set_env GATEWAY_COPY_RATE 600 ;;
  restore) take_lock; unset_env GATEWAY_COPY_RATE ;;
  show) echo "GATEWAY_COPY_RATE=$(env_value GATEWAY_COPY_RATE)"; exit 0 ;;
  *) die "usage: assay-copy-limit lift | restore | show" ;;
esac
compose up -d --wait --wait-timeout "$ASSAY_WAIT_TIMEOUT" --no-deps api-gateway
rate="$(env_value GATEWAY_COPY_RATE)"
log "demo copies per second per visitor: ${rate:-the default, 1 a minute}"
