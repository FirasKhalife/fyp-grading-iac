#!/usr/bin/env bash
# Installs the tools live/ needs into ~/.local (no sudo): OpenTofu, ShellCheck, uv, and through uv a Python 3.13
# with ansible-core and ansible-lint, then the Ansible collections. Every download is pinned and checked against a
# SHA-256 sum. Safe to run again: it skips what is already at the pinned version.
#
#   live/tools.sh        (from WSL Ubuntu; make sure ~/.local/bin is on PATH)
set -euo pipefail

TOFU_VERSION=1.13.9
TOFU_SHA256=b34b327cc1ef07178207b6f2cd1f5276537d3e5b7be316500f6dac50d4c0a857
SHELLCHECK_VERSION=0.11.0
SHELLCHECK_SHA256=8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198
UV_VERSION=0.13.9
UV_SHA256=a7fbaff2b9a271d85c1bdb540941090fd1ce011797b4abeb48e4dcd39c2471d5
ANSIBLE_CORE_VERSION=2.22.0
ANSIBLE_LINT_VERSION=26.11.0

LIVE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.local/bin"
mkdir -p "$BIN"
export PATH="$BIN:$PATH"
[ "$(uname -m)" = x86_64 ] || { echo "tools: only x86_64 is pinned here" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# fetch <url> <sha256>: downloads into $TMP and checks the sum.
fetch() {
  local file="$TMP/${1##*/}"
  curl -fsSL --retry 3 -o "$file" "$1"
  echo "$2  $file" | sha256sum -c --quiet - || { echo "tools: checksum mismatch for $1" >&2; exit 1; }
  printf '%s' "$file"
}

if [ "$(tofu version 2>/dev/null | head -n 1)" != "OpenTofu v$TOFU_VERSION" ]; then
  f="$(fetch "https://github.com/opentofu/opentofu/releases/download/v$TOFU_VERSION/tofu_${TOFU_VERSION}_linux_amd64.tar.gz" "$TOFU_SHA256")"
  tar -xzf "$f" -C "$TMP" tofu && install -m 0755 "$TMP/tofu" "$BIN/tofu"
fi

if ! shellcheck --version 2>/dev/null | grep -qx "version: $SHELLCHECK_VERSION"; then
  f="$(fetch "https://github.com/koalaman/shellcheck/releases/download/v$SHELLCHECK_VERSION/shellcheck-v$SHELLCHECK_VERSION.linux.x86_64.tar.xz" "$SHELLCHECK_SHA256")"
  tar -xJf "$f" -C "$TMP" && install -m 0755 "$TMP/shellcheck-v$SHELLCHECK_VERSION/shellcheck" "$BIN/shellcheck"
fi

if [ "$(uv --version 2>/dev/null | awk '{print $2}')" != "$UV_VERSION" ]; then
  f="$(fetch "https://github.com/astral-sh/uv/releases/download/$UV_VERSION/uv-x86_64-unknown-linux-gnu.tar.gz" "$UV_SHA256")"
  tar -xzf "$f" -C "$TMP" && install -m 0755 "$TMP"/uv-x86_64-unknown-linux-gnu/uv "$TMP"/uv-x86_64-unknown-linux-gnu/uvx "$BIN/"
fi

# ansible-core 2.22 needs Python 3.13 on this side; uv downloads one if the system has none.
uv tool install --quiet --python 3.13 "ansible-core==$ANSIBLE_CORE_VERSION"
uv tool install --quiet --python 3.13 "ansible-lint==$ANSIBLE_LINT_VERSION" --with "ansible-core==$ANSIBLE_CORE_VERSION"

(cd "$LIVE/ansible" && ANSIBLE_CONFIG="$LIVE/ansible/ansible.cfg" ansible-galaxy collection install --upgrade -r requirements.yml -p collections >/dev/null)

tofu version | head -n 1
shellcheck --version | sed -n 2p
uv --version
ansible --version | head -n 1
ansible-lint --version | head -n 1
