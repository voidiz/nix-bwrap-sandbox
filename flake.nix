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
          nix

          curl
          git
          jq

          neovim
          less
          fd
          ripgrep
          # ps, etc.
          procps
          unzip
          which
          htop

          pi-coding-agent
          kiro-cli

          bash-completion
          bashInteractive
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
