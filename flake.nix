{
  description = "Deployment tool for multiple NixOS systems";

  edition = 201909;
  
  inputs.nixpkgs.url = "github:nixos/nixpkgs/3320a06049fc259e87a2bd98f4cd42f15f746b96";

  outputs = { self, nixpkgs }: {
    lib.nixus = conf: let
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
    in result.config.deployScript // result // nixusPkgs.lib.mapAttrs (n: v: v.deployScript) result.config.nodes;
  };
}
