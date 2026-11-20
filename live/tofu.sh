#!/usr/bin/env bash
# Runs OpenTofu in live/tofu with the Cloudflare credentials and the state passphrase from a local file, so they are
# never typed, printed or committed.
#
#   live/tofu.sh init | plan | apply | output | ...      (any tofu command and its arguments)
#
# ASSAY_CLOUDFLARE_ENV picks the file (default ~/.config/assay/cloudflare.env). It must set CLOUDFLARE_API_TOKEN,
# TF_VAR_cloudflare_account_id and TF_VAR_state_passphrase, and be readable by you only (chmod 600).
set -euo pipefail

LIVE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ASSAY_CLOUDFLARE_ENV:-$HOME/.config/assay/cloudflare.env}"

[ -f "$ENV_FILE" ] || { echo "tofu.sh: $ENV_FILE is missing (see live/README.md, step 2)" >&2; exit 1; }
if [ -n "$(find "$ENV_FILE" -perm /077)" ]; then
  echo "tofu.sh: $ENV_FILE is readable by others; run: chmod 600 $ENV_FILE" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a
for name in CLOUDFLARE_API_TOKEN TF_VAR_cloudflare_account_id TF_VAR_state_passphrase; do
  [ -n "${!name:-}" ] || { echo "tofu.sh: $name is not set in $ENV_FILE" >&2; exit 1; }
done

exec tofu -chdir="$LIVE/tofu" "$@"
