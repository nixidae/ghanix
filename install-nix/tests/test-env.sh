#!/usr/bin/env bash
# Post-install smoke test. Runs on the runner, after the install step.
set -euo pipefail

fail=0
check() {
  if eval "$2"; then
    echo "ok: $1"
  else
    echo "FAIL: $1"
    fail=1
  fi
}

check "NIX_PROFILES is set" '[[ -n "${NIX_PROFILES:-}" ]]'
check "NIX_SSL_CERT_FILE names a file" '[[ -f "${NIX_SSL_CERT_FILE:-/nonexistent}" ]]'
check "PATH holds a Nix profile" '[[ "$PATH" == *".nix-profile"* || "$PATH" == *"nix/profile"* ]]'
check "nix runs" 'command -v nix >/dev/null'

if [[ "$fail" == "0" ]]; then
  nix --version
fi
exit "$fail"
