conf: let
  nixpkgs = import ./nixpkgs.nix;

  pkgs = import nixpkgs {
    config = {};
    overlays = [
      (self: super: {
        lib = super.lib.extend (import ./dag.nix);
      })
    ];
  };

  result = pkgs.lib.evalModules {
    modules = [
      ./options.nix
      conf
      { _module.args.pkgs = pkgs; }
    ];
  };
in result.config.deployScript // result
