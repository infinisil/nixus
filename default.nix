conf: let
  nixpkgs = import ./nixpkgs.nix;

  nixusPkgs = import nixpkgs {
    config = {};
    overlays = [
      (self: super: {
        lib = super.lib.extend (import ./dag.nix);
      })
    ];
  };

  result = nixusPkgs.lib.evalModules {
    modules = [
      modules/options.nix
      modules/deploy.nix
      modules/secrets.nix
      conf
      # Not naming it pkgs to avoid confusion and trouble for overriding scopes
      { _module.args.nixusPkgs = nixusPkgs; }
    ];
  };
in result.config.deployScript // result // nixusPkgs.lib.mapAttrs (n: v: v.combinedDeployScript) result.config.nodes
