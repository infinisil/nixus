{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { nixpkgs, flake-utils, self, ... }:
    {
      buildNixus = import ./build.nix {
        # Set the default nixpkgs argument, can be overridden with follows
        inherit nixpkgs;
        deploySystem = throw "buildNixus: The first argument needs to have the `deploySystem` attribute";
      };
    }
    // flake-utils.lib.eachDefaultSystem (system: {

      packages.example = self.buildNixus {
        deploySystem = system;
      } ./example/deploy.nix;

    });
}
