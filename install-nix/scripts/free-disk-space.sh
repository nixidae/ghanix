#!/usr/bin/env bash
# Delete what the runner image ships and no Nix job uses, then report.
# Linux only; every path below is one. `;` and not `&&`, so a prune that
# fails still leaves the second df to report the number.
set -euo pipefail

[[ "$(uname -s)" == "Linux" ]] || exit 0

df -h /
# A glob that matches nothing reaches rm literally; -f makes that silent,
# which is what julia* relies on.
sudo rm -rf \
  /usr/lib/jvm \
  /usr/share/dotnet \
  /usr/share/swift \
  /usr/local/.ghcup \
  /usr/local/julia* \
  /usr/local/lib/android \
  /opt/az \
  /usr/local/share/powershell \
  /usr/local/share/chromium \
  /opt/microsoft \
  /opt/google \
  /usr/lib/firefox
# /opt/hostedtoolcache is not on this list on purpose: setup-* actions
# install there at run time, and deleting it breaks them.
docker system prune --all --force
docker builder prune --all --force
df -h /
