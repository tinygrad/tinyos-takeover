{
  description = "tinyos takeover";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.tinyturing.url = "github:tinygrad/tinyturing";
  inputs.tinyos = {
    url = "github:tinygrad/tinyos/dev";
    flake = false;
  };

  outputs =
    inputs@{
      nixpkgs,
      flake-utils,
      ...
    }:
    let
      overlays = [
        inputs.tinyturing.overlays.default
      ];
      pkgs = import nixpkgs {
        inherit overlays;
        system = "x86_64-linux";
      };
    in
    {
      devShells.x86_64-linux.default = pkgs.mkShell { };
    }
    // {
      nixosConfigurations.takeover = pkgs.nixos {
        _module.args = { inherit inputs; };
        imports = [
          ./system.nix
        ];
        nixpkgs.overlays = overlays;
      };
    };
}
