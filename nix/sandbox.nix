{ pkgs, nixpkgs, self }:
pkgs.mkShell {
  shell = pkgs.bashInteractive;

  packages = with pkgs; [
    # Subset of NixOS `environment.corePackages`
    # (nixos/modules/config/system-path.nix)
    gnugrep
    gnused
    gawk
    findutils
    diffutils
    gnupatch
    gnutar
    gzip
    bzip2
    xz
    zstd
    util-linux
    time

    nix
    bubblewrap

    curl
    git
    jq

    neovim
    less
    fd
    ripgrep
    procps
    unzip
    which
    htop

    uv
    nodejs
    python3

    pi-coding-agent
    kiro-cli

    bash-completion
  ];

  shellHook = ''
    export SHELL=${pkgs.bashInteractive}/bin/bash
    export NIX_PATH=nixpkgs=${nixpkgs}
    echo "nixpkgs: nixpkgs-unstable (${self.inputs.nixpkgs.lastModifiedDate} - ${self.inputs.nixpkgs.shortRev})"
  '';
}
