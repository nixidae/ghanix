#!/usr/bin/env bash
# Let the runner open an unprivileged user namespace, which Ubuntu denies
# by default. The Nix sandbox needs one, and so does passt, which unshares
# one before serving a guest uplink and exits at startup if it cannot.
# The unshare proves the sysctls took, here rather than in the first test
# that needs them.
set -euo pipefail

[[ "$(uname -s)" == "Linux" ]] || exit 0

sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
sudo sysctl -w kernel.unprivileged_userns_clone=1
unshare --user --map-root-user --mount --pid --fork --mount-proc true
