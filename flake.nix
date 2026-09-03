{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = nixpkgs.lib.genAttrs systems;
    pkgsFor = system:
      import nixpkgs {
        inherit system;

        # for kiro-cli
        config.allowUnfree = true;
      };
  in {
    # Devshell used inside the bwrap
    devShells = forAllSystems (system: let
      pkgs = pkgsFor system;
    in {
      default = import ./nix/sandbox.nix {
        inherit pkgs nixpkgs self;
      };
    });

    packages = forAllSystems (system: let
      pkgs = pkgsFor system;
    in {
      bwrap-sandbox = pkgs.callPackage ./nix/package.nix {inherit self;};
    });

    apps = forAllSystems (system: let
      pkg = self.packages.${system}.bwrap-sandbox;
    in {
      nbs = {
        type = "app";
        program = "${pkg}/bin/bwrap-sandbox";
      };
    });
  };
}
