{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["x86_64-linux"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
    pkgsFor = system:
      import nixpkgs {
        inherit system;

        # for kiro-cli
        config.allowUnfree = true;
      };
  in {
    devShells = forAllSystems (system: let
      pkgs = pkgsFor system;
    in {
      default = pkgs.mkShell {
        shell = pkgs.bashInteractive;

        # Base packages for the sandbox
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
      };
    });
  };
}
