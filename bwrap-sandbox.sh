#!/usr/bin/env bash

# Usage:
#
# Interactive shell:
# ./bwrap-sandbox.sh
#
# Run command inside sandbox:
# ./bwrap-sandbox.sh -- echo "hi"
#
# Pass additional flags to bwrap
# ./bwrap-sandbox --ro-bind /example /example

set -euo pipefail

script_dir="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
flake_dir="${BWRAP_SANDBOX_FLAKE_DIR:-$script_dir}"

die() {
  echo "error: $*" >&2
  exit 1
}

check_host_dependencies() {
  command -v nix >/dev/null 2>&1 || die "nix not found on PATH"
}

enter_devshell() {
  # Can't use nix develop on flake inside /nix/store, so copy it out if this
  # script was installed using nix
  local flake_ref="$flake_dir"
  if [[ "$flake_dir" == /nix/store/* ]]; then
    local key cache_dir
    key="$(printf '%s' "$flake_dir" | sha256sum | cut -d' ' -f1)"
    cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/nix-bwrap-sandbox/flakes/$key"
    rm -rf "$cache_dir"

    mkdir -p "$(dirname "$cache_dir")"
    cp -r "$flake_dir" "$cache_dir"
    chmod -R u+w "$cache_dir"
    flake_ref="$cache_dir"
  fi

  # Re-execute this script inside the devshell. The env variable puts us in the
  # second phase of the script which starts the bwrap.
  exec nix --extra-experimental-features "nix-command flakes" develop \
    --accept-flake-config "$flake_ref" \
    --command env BWRAP_SANDBOX_IN_DEVSHELL=1 "$0" "$@"
}

check_sandbox_dependencies() {
  command -v bwrap >/dev/null 2>&1 || die "bwrap not found on PATH"
}

resolve_paths() {
  bash_path="$(readlink -f "$(command -v bash)")"

  script_bin="$(command -v script 2>/dev/null || true)"
  script_bin="$(readlink -f "$script_bin")"

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
    die "no CA bundle found, set SSL_CERT_FILE to your CA bundle and retry"
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

  sandbox_home="$(mktemp -d "${TMPDIR:-/tmp}/sandbox-home-XXXXXX")"

  # Copy over configuration files
  cp -a "$script_dir/sandbox-home/." "$sandbox_home/" 2>/dev/null || true
  chmod u+w "$sandbox_home"
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
}

build_sandbox_path() {
  local entries entry
  local kept=""

  # Filter for only PATH entries added by `nix develop`
  IFS=':' read -ra entries <<< "$PATH"
  for entry in "${entries[@]}"; do
    if [[ "$entry" == /nix/store/* ]]; then
      kept="$kept$entry:"
    fi
  done

  echo "${kept}/bin:/usr/bin"
}

build_sandbox_env() {
  sandbox_env=()

  sandbox_env+=(--setenv PATH "$(build_sandbox_path)")
  sandbox_env+=(--setenv SHELL "${SHELL:-/bin/bash}")
  sandbox_env+=(--setenv HOME "$sandbox_home")
  sandbox_env+=(--setenv TMPDIR /tmp)
  sandbox_env+=(--setenv TERM "${TERM:-xterm-256color}")
  [[ -n "${NIX_PATH:-}" ]] && sandbox_env+=(--setenv NIX_PATH "$NIX_PATH")
}

main() {
  if [[ -z "${BWRAP_SANDBOX_IN_DEVSHELL:-}" ]]; then
    check_host_dependencies
    enter_devshell "$@"
  fi

  check_sandbox_dependencies
  resolve_paths

  sandbox_passwd=$(mktemp /tmp/sandbox-passwd-XXXXXX)
  sandbox_group=$(mktemp /tmp/sandbox-group-XXXXXX)

  cleanup() {
    rm -f "$sandbox_passwd" "$sandbox_group"
    if [[ -n "${sandbox_home:-}" ]]; then
      rm -rf "$sandbox_home" 2>/dev/null || {
        # nix run/shell/build inside the sandbox leaves a chroot store with
        # read-only permissions under the sandbox HOME. Make it writable and
        # retry
        chmod -R u+w "$sandbox_home"
        rm -rf "$sandbox_home"
      }
    fi
  }
  trap cleanup EXIT

  setup_sandbox_home "$flake_dir"

  local host_uid host_gid
  host_uid="$(id -u)"
  host_gid="$(id -g)"

  echo "nixuser:x:${host_uid}:${host_gid}:sandbox user:${sandbox_home}:/bin/bash" >>"$sandbox_passwd"
  echo "nixuser:x:${host_gid}:" >>"$sandbox_group"

  build_binds
  build_sandbox_env

  local -a extra_flags=()
  if [[ "${1:-}" == "--" ]]; then
    shift
  elif [[ "${1:-}" == -* ]]; then
    while [[ $# -gt 0 && "$1" != "--" ]]; do
      extra_flags+=("$1")
      shift
    done
    if [[ "${1:-}" == "--" ]]; then
      shift
    fi
  fi

  # Default to $SHELL (with /bin/bash fallback) if no command was passed
  local -a cmd
  if [[ $# -eq 0 ]]; then
    cmd=("${SHELL:-/bin/bash}" -i)
  else
    cmd=("$@")
  fi
  local inner_cmd
  inner_cmd="$(printf "%q " "${cmd[@]}")"

  bwrap \
    --clearenv \
    --unshare-all \
    --share-net \
    --die-with-parent \
    --new-session \
    --ro-bind /nix/store /nix/store \
    --ro-bind-try /bin/sh /bin/sh \
    --ro-bind "$bash_path" /bin/bash \
    "${binds[@]}" \
    --ro-bind /etc/resolv.conf /etc/resolv.conf \
    --ro-bind /etc/hosts /etc/hosts \
    --ro-bind /etc/nsswitch.conf /etc/nsswitch.conf \
    --ro-bind-try /etc/localtime /etc/localtime \
    --ro-bind "$sandbox_passwd" /etc/passwd \
    --ro-bind "$sandbox_group" /etc/group \
    --tmpfs /tmp \
    --proc /proc \
    --dev /dev \
    --tmpfs /dev/shm \
    --bind "$PWD" "$PWD" \
    --bind "$sandbox_home" "$sandbox_home" \
    "${extra_flags[@]}" \
    "${sandbox_env[@]}" \
    --chdir "$PWD" \
    "$script_bin" -qec "$inner_cmd" /dev/null
}

main "$@"
