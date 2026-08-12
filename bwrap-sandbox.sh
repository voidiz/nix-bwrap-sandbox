#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

check_dependencies() {
  local missing=()
  local bin
  for bin in bwrap nix script; do
    command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "missing required binaries: ${missing[*]}" >&2
    exit 1
  fi
}

resolve_paths() {
  nix_bin=$(readlink -f "$(command -v nix)")

  bash_path="/bin/bash"
  [[ ! -f "$bash_path" ]] && command -v bash &>/dev/null && bash_path=$(command -v bash)
  [[ ! -f "$bash_path" ]] && [[ -f /bin/sh ]] && bash_path=/bin/sh

  ssl_cert=""
  local candidate
  for candidate in \
    "${NIX_SSL_CERT_FILE:-}" \
    "${SSL_CERT_FILE:-}" \
    /etc/ssl/certs/ca-certificates.crt \
    /etc/ssl/ca-bundle.pem \
    /etc/ssl/certs/ca-bundle.crt \
    /etc/pki/tls/certs/ca-bundle.crt \
    /nix/store/*-nss-cacert-*/etc/ssl/certs/ca-bundle.crt; do

    [[ -z "$candidate" ]] && continue

    candidate="$(readlink -f "$candidate" 2>/dev/null || true)"
    if [[ -n "$candidate" && -f "$candidate" ]]; then
      ssl_cert="$candidate"
      break
    fi
  done

  if [[ -z "$ssl_cert" ]]; then
    echo "error: no CA bundle found; TLS downloads inside the sandbox will fail" >&2
    echo "         set NIX_SSL_CERT_FILE to your CA bundle and retry" >&2
    exit 1
  fi

  # script(1) is used below to run nix under a pty from the devtmpfs inside
  # the bwrap
  script_bin=$(command -v script 2>/dev/null || true)
  if [[ -n "$script_bin" ]]; then
    script_bin=$(readlink -f "$script_bin")
  fi
}

# Copy "$1" into the sandbox home directory while resolving symlinks
seed_sandbox_home_dir() {
  local src="$1" name dest real

  name="$(basename "$src")"
  dest="$sandbox_home/$name"
  real="$(readlink -f "$src" 2>/dev/null || true)"

  if [[ -z "$real" || ! -d "$real" ]]; then
    return 1
  fi

  mkdir -p "$dest"
  cp -a "$real/." "$dest/"
}

# Copy the single file "$1" (relative to $HOME) into the sandbox home directory
# while resolving symlinks
seed_sandbox_home_file() {
  local rel="$1" src dest

  src="$HOME/$rel"
  dest="$sandbox_home/$rel"

  [[ -f "$src" ]] || return 1

  mkdir -p "$(dirname "$dest")"
  cp -pL "$src" "$dest"
}

# One temporary home directory for each sandbox
setup_sandbox_home() {
  local script_dir="$1"

  sandbox_home="$(mktemp -d "$script_dir/sandbox-home-XXXXXX")"

  # Copy over configuration files
  cp -a "$script_dir/sandbox-home/." "$sandbox_home/" 2>/dev/null || true
  seed_sandbox_home_dir "$HOME/.pi" || true
  seed_sandbox_home_dir "$HOME/.kiro" || true

  # Auth token for kiro
  seed_sandbox_home_file ".local/share/kiro-cli/data.sqlite3" || true
}

build_binds() {
  binds=()

  [[ -d /usr/bin ]] && binds+=(--ro-bind /usr/bin /usr/bin)
  [[ -d /usr/lib ]] && binds+=(--ro-bind /usr/lib /usr/lib)
  [[ -d /usr/lib64 ]] && binds+=(--ro-bind /usr/lib64 /usr/lib64 --symlink /usr/lib64 /lib64)
  [[ -n "$ssl_cert" ]] && binds+=(--ro-bind "$ssl_cert" /etc/ssl/certs/ca-certificates.crt --setenv SSL_CERT_FILE /etc/ssl/certs/ca-certificates.crt --setenv CURL_CA_BUNDLE /etc/ssl/certs/ca-certificates.crt)
  [[ -n "${XDG_RUNTIME_DIR:-}" ]] && binds+=(--bind "${XDG_RUNTIME_DIR}" "${XDG_RUNTIME_DIR}" --setenv XDG_RUNTIME_DIR "${XDG_RUNTIME_DIR}")
}

main() {
  check_dependencies
  resolve_paths

  sandbox_passwd=$(mktemp /tmp/sandbox-passwd-XXXXXX)
  sandbox_group=$(mktemp /tmp/sandbox-group-XXXXXX)

  cleanup() {
    rm -f "$sandbox_passwd" "$sandbox_group"
    [[ -n "${sandbox_home:-}" ]] && rm -rf "$sandbox_home"
  }
  trap cleanup EXIT

  setup_sandbox_home "$script_dir"

  local host_uid host_gid
  host_uid="$(id -u)"
  host_gid="$(id -g)"

  echo "nixuser:x:${host_uid}:${host_gid}:sandbox user:${sandbox_home}:/bin/bash" >>"$sandbox_passwd"
  echo "nixuser:x:${host_gid}:" >>"$sandbox_group"

  build_binds

  # Activate the devshell when entering the bwrap, and forward the positional
  # args passed to this script or fall back to bash
  local nix_cmd
  nix_cmd=$(printf "%q " "$nix_bin" --extra-experimental-features "nix-command flakes" develop --accept-flake-config "$script_dir" -c "${@:-bash}")

  bwrap \
    --clearenv \
    --share-net \
    --unshare-pid \
    --die-with-parent \
    --new-session \
    --unshare-uts \
    --bind /nix/store /nix/store \
    --bind /nix/var/nix /nix/var/nix \
    --tmpfs /nix/var/nix/builds \
    --ro-bind-try /bin/sh /bin/sh \
    --ro-bind "$bash_path" /bin/bash \
    --ro-bind "$nix_bin" /usr/bin/nix \
    "${binds[@]}" \
    --ro-bind /etc/resolv.conf /etc/resolv.conf \
    --ro-bind /etc/hosts /etc/hosts \
    --ro-bind /etc/nsswitch.conf /etc/nsswitch.conf \
    --ro-bind "$sandbox_passwd" /etc/passwd \
    --ro-bind "$sandbox_group" /etc/group \
    --ro-bind-try /etc/ld.so.cache /etc/ld.so.cache \
    --bind "$PWD" "$PWD" \
    --bind "$script_dir" "$script_dir" \
    --tmpfs /tmp \
    --proc /proc \
    --dev /dev \
    --tmpfs /dev/shm \
    --ro-bind-try /sys /sys \
    --ro-bind-try /etc/machine-id /etc/machine-id \
    --ro-bind-try /var/lib/dbus/machine-id /var/lib/dbus/machine-id \
    --ro-bind-try /run/dbus/system_bus_socket /run/dbus/system_bus_socket \
    \
    --ro-bind-try /etc/localtime /etc/localtime \
    --ro-bind-try /etc/hostname /etc/hostname \
    \
    --setenv HOME "$sandbox_home" \
    --setenv PATH "/bin:/usr/bin" \
    --setenv TMPDIR /tmp \
    --setenv TERM "${TERM:-xterm-256color}" \
    --chdir "$PWD" \
    "${script_bin:-script}" -qec "$nix_cmd" /dev/null
}

main "$@"
