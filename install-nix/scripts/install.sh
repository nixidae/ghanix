#!/usr/bin/env bash
# Install Nix with nixos/nix-installer, then point the job at it.
#
# Reads INPUT_* from the environment (the composite action maps its inputs
# there), so it also runs outside Actions with GITHUB_ENV and GITHUB_PATH
# pointed at files.
set -euo pipefail

if nix_path="$(type -p nix)"; then
  echo "Aborting: Nix is already installed at ${nix_path}"
  exit 0
fi

arch="$(uname -m)"
case "$arch" in
  x86_64) arch="x86_64" ;;
  aarch64 | arm64) arch="aarch64" ;;
  *)
    echo "::error::unsupported architecture: $(uname -m)"
    exit 1
    ;;
esac

os="${RUNNER_OS:-$(uname -s)}"
case "$os" in
  Linux | linux) os="linux" ;;
  macOS | macos | Darwin | darwin) os="darwin" ;;
  *)
    echo "::error::unsupported OS: $os"
    exit 1
    ;;
esac

if [[ "$os" == "darwin" && "$arch" == "x86_64" ]]; then
  echo "::error::nix-installer supports no x86_64-darwin; use an Apple Silicon runner"
  exit 1
fi

echo "::group::Downloading nix-installer"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
version="${INPUT_INSTALLER_VERSION:-2.35.2}"
url="https://github.com/NixOS/nix-installer/releases/download/${version}/nix-installer-${arch}-${os}"
curl -sS --fail -L --retry 5 --retry-all-errors -o "$workdir/nix-installer" "$url"
chmod +x "$workdir/nix-installer"
echo "::endgroup::"

echo "::group::Writing nix.conf"
conf="$workdir/nix.conf"
add_conf() { printf '%s\n' "$1" >>"$conf"; }
extra="${INPUT_EXTRA_CONF:-}"
add_conf "show-trace = true"
add_conf "max-jobs = auto"
if [[ "$os" == "darwin" ]]; then
  add_conf "ssl-cert-file = /etc/ssl/cert.pem"
fi
if [[ "${INPUT_TRUST_RUNNER_USER:-true}" == "true" ]]; then
  add_conf "trusted-users = root $(id -un)"
fi
token="${INPUT_GITHUB_ACCESS_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -n "$token" && "$extra" != *"access-tokens"* ]]; then
  add_conf "access-tokens = github.com=$token"
fi
features="${INPUT_EXPERIMENTAL_FEATURES:-nix-command flakes}"
if [[ -n "$features" && "$extra" != *"experimental-features"* ]]; then
  add_conf "experimental-features = $features"
fi
if [[ "$extra" != *"always-allow-substitutes"* ]]; then
  add_conf "always-allow-substitutes = true"
fi
if [[ "$os" == "linux" && -e /dev/kvm && "$extra" != *"extra-system-features"* ]]; then
  add_conf "extra-system-features = kvm"
fi
if [[ -n "$extra" ]]; then
  add_conf "$extra"
fi
echo "::endgroup::"

echo "::group::Installing Nix"
args=(install --no-confirm --explain --extra-conf "$(cat "$conf")")
# A string and not an array: on macOS `shell: bash` is bash 3.2, where
# expanding an empty array under `set -u` fails.
planner=""
if [[ "$os" == "linux" ]]; then
  planner="linux"
  if [[ "$(cat /proc/1/comm 2>/dev/null || echo unknown)" != "systemd" ]]; then
    args+=(--init none)
    no_init=true
  fi
elif [[ "${INPUT_CASE_SENSITIVE:-true}" == "true" ]]; then
  args+=(--case-sensitive)
fi
echo "sudo $workdir/nix-installer $planner ${args[*]}"
if [[ -n "$planner" ]]; then
  sudo "$workdir/nix-installer" "$planner" "${args[@]}"
else
  sudo "$workdir/nix-installer" "${args[@]}"
fi
echo "::endgroup::"

if [[ "${no_init:-false}" == "true" ]]; then
  echo "::group::Starting nix-daemon (no init system)"
  sudo /nix/var/nix/profiles/default/bin/nix-daemon &
  for _ in {1..300}; do
    [[ -S /nix/var/nix/daemon-socket/socket ]] && break
    sleep 0.1
  done
  if [[ ! -S /nix/var/nix/daemon-socket/socket ]]; then
    echo "::error::nix-daemon socket never appeared"
    exit 1
  fi
  echo "::endgroup::"
fi

# What follows mirrors the profile scripts the installer ships
# (nix-daemon.sh), which Actions never sources on its own.
if [[ -z "${TMPDIR:-}" && -n "${RUNNER_TEMP:-}" ]]; then
  echo "TMPDIR=${RUNNER_TEMP}" >>"${GITHUB_ENV:?}"
fi

if [[ -n "${NIX_STATE_HOME:-}" ]]; then
  NIX_LINK="$NIX_STATE_HOME/profile"
else
  NIX_LINK="$HOME/.nix-profile"
fi
echo "NIX_PROFILES=/nix/var/nix/profiles/default $NIX_LINK" >>"$GITHUB_ENV"

if [[ -z "${NIX_SSL_CERT_FILE:-}" ]]; then
  if [[ -e "/etc/ssl/certs/ca-certificates.crt" ]]; then
    echo "NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt" >>"$GITHUB_ENV"
  elif [[ "$os" == "darwin" && -e "/etc/ssl/cert.pem" ]]; then
    echo "NIX_SSL_CERT_FILE=/etc/ssl/cert.pem" >>"$GITHUB_ENV"
  elif [[ -e "/etc/pki/tls/certs/ca-bundle.crt" ]]; then
    echo "NIX_SSL_CERT_FILE=/etc/pki/tls/certs/ca-bundle.crt" >>"$GITHUB_ENV"
  elif [[ -e "/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt" ]]; then
    echo "NIX_SSL_CERT_FILE=/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt" >>"$GITHUB_ENV"
  elif [[ -e "$NIX_LINK/etc/ssl/certs/ca-bundle.crt" ]]; then
    echo "NIX_SSL_CERT_FILE=$NIX_LINK/etc/ssl/certs/ca-bundle.crt" >>"$GITHUB_ENV"
  fi
fi

echo "/nix/var/nix/profiles/default/bin" >>"$GITHUB_PATH"
echo "$NIX_LINK/bin" >>"$GITHUB_PATH"
