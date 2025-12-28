{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        # pkgs = nixpkgs.legacyPackages.${system};
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.beamMinimal28Packages.elixir_1_19
            pkgs.beamMinimal28Packages.elixir-ls
          ];
        };
      }
    );
}
