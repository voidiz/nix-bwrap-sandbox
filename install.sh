#!/usr/bin/env bash

# Installs bwrap-sandbox to "$HOME/.local/bin"
#   ./install.sh
#   ./install.sh --uninstall
#   curl -fsSL https://raw.githubusercontent.com/voidiz/nix-bwrap-sandbox/main/install.sh | bash

set -euo pipefail

repo_url="${REPO_URL:-https://github.com/voidiz/nix-bwrap-sandbox}"
install_dir="${INSTALL_DIR:-$HOME/.local/share/nix-bwrap-sandbox}"
bin_dir="${BIN_DIR:-$HOME/.local/bin}"
bin_name="${BIN_NAME:-bwrap-sandbox}"

usage() {
  cat <<EOF
usage: ${0##*/} [--uninstall] [-h]

Installs nix-bwrap-sandbox: clones (or updates) the repo to
  $install_dir
and symlinks the launcher to
  $bin_dir/$bin_name

Options:
  --uninstall   remove the symlink and the cloned repo
  -h, --help    show this help

Environment:
  REPO_URL, INSTALL_DIR, BIN_DIR   override the defaults
EOF
}

uninstall() {
  local removed=0
  if [[ -L "$bin_dir/$bin_name" ]]; then
    rm "$bin_dir/$bin_name"
    echo "removed symlink: $bin_dir/$bin_name"
    removed=1
  fi

  if [[ -d "$install_dir/.git" ]]; then
    rm -rf "$install_dir"
    echo "removed install: $install_dir"
    removed=1
  fi

  if ((removed == 0)); then
    echo "nothing to uninstall" >&2
  fi
}

case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
--uninstall)
  uninstall
  exit 0
  ;;
"")
  # default: install
  ;;
*)
  echo "unknown option: $1" >&2
  usage >&2
  exit 1
  ;;
esac

mkdir -p "$bin_dir"

if [[ -d "$install_dir/.git" ]]; then
  echo "updating $install_dir"
  git -C "$install_dir" pull --ff-only
else
  mkdir -p "$(dirname "$install_dir")"
  git clone "$repo_url" "$install_dir"
fi

ln -sf "$install_dir/bwrap-sandbox.sh" "$bin_dir/$bin_name"

echo "installed: $bin_dir/$bin_name"
if [[ ":$PATH:" != *":$bin_dir:"* ]]; then
  echo "note: $bin_dir is not on your PATH. add it, e.g. in ~/.bashrc:"
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi
