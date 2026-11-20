#!/usr/bin/env bash
# Offline checks of everything in live/: nothing here talks to Cloudflare or the server.
#
#   live/check.sh        (after live/tools.sh; CI runs the same script)
#
# tofu fmt and validate (with a throwaway passphrase: there is no state), ansible-lint, ansible-playbook
# --syntax-check of every playbook against the example inventory, and ShellCheck on every script.
set -euo pipefail

LIVE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ANSIBLE_CONFIG="$LIVE/ansible/ansible.cfg"

echo "== tofu fmt"
tofu -chdir="$LIVE/tofu" fmt -check -diff -recursive

echo "== tofu validate"
export TF_VAR_state_passphrase=offline-validate-only
export TF_VAR_cloudflare_account_id=00000000000000000000000000000000
tofu -chdir="$LIVE/tofu" init -backend=false -input=false >/dev/null
tofu -chdir="$LIVE/tofu" validate

echo "== ansible-playbook --syntax-check"
cd "$LIVE/ansible"
for playbook in bootstrap.yml site.yml backup-env.yml; do
  ASSAY_TUNNEL_TOKEN=offline ansible-playbook -i inventory.example.yml --syntax-check "$playbook"
done

echo "== ansible-lint"
ansible-lint --offline

echo "== shellcheck"
cd "$LIVE"
shellcheck -x ./*.sh
(cd ansible/roles/assay/files && shellcheck -x ./*.sh)

echo "All checks passed."
