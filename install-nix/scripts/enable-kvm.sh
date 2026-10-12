#!/usr/bin/env bash
# Let the runner user open /dev/kvm. Tolerates runners with no KVM and
# containers with no udev: both only mean there is nothing to do.
set -euo pipefail

[[ "$(uname -s)" == "Linux" ]] || exit 0

if [[ ! -e /dev/kvm ]]; then
  echo "No /dev/kvm on this runner"
  exit 0
fi
if [[ ! -d /etc/udev/rules.d ]] || ! command -v udevadm >/dev/null 2>&1; then
  echo "/dev/kvm exists but udev is unavailable; assuming the device is already accessible"
  exit 0
fi

echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' |
  sudo tee /etc/udev/rules.d/99-ghanix-kvm.rules
sudo udevadm control --reload-rules || true
sudo udevadm trigger --name-match=kvm || true
ls -l /dev/kvm
