#!/usr/bin/env bash
# Runs an Ansible playbook from live/ansible against the server in live/ansible/inventory.yml.
#
#   live/deploy.sh                       site.yml: harden, install Docker, deploy or update the stack
#   live/deploy.sh bootstrap [-k]        bootstrap.yml: once, as root, on a fresh server (-k: root's password)
#   live/deploy.sh backup-env            backup-env.yml: an encrypted copy of the host's .env
#   live/deploy.sh site --check --diff   any ansible-playbook options after the playbook name
#
# For site.yml, the tunnel token is read from the OpenTofu state (live/tofu.sh output) into ASSAY_TUNNEL_TOKEN, so
# it is never printed or written to disk here. Export ASSAY_TUNNEL_TOKEN yourself to skip that.
set -euo pipefail

LIVE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ANSIBLE_CONFIG="$LIVE/ansible/ansible.cfg"

playbook=site
case "${1:-}" in
  site | bootstrap | backup-env) playbook="$1"; shift ;;
  -* | '') ;;
  *) echo "deploy.sh: unknown playbook '$1' (site, bootstrap, backup-env)" >&2; exit 2 ;;
esac

[ -f "$LIVE/ansible/inventory.yml" ] || {
  echo "deploy.sh: copy live/ansible/inventory.example.yml to inventory.yml and put in the server's address" >&2
  exit 1
}
[ -d "$LIVE/ansible/collections/ansible_collections" ] || {
  echo "deploy.sh: the Ansible collections are missing; run live/tools.sh" >&2
  exit 1
}

if [ "$playbook" = site ] && [ -z "${ASSAY_TUNNEL_TOKEN:-}" ]; then
  ASSAY_TUNNEL_TOKEN="$("$LIVE/tofu.sh" output -raw tunnel_token)" || {
    echo "deploy.sh: couldn't read the tunnel token from the OpenTofu state; run live/tofu.sh apply first" >&2
    exit 1
  }
  export ASSAY_TUNNEL_TOKEN
fi

cd "$LIVE/ansible"
exec ansible-playbook "$playbook.yml" "$@"
