nixusArgs: conf: let
  nixpkgs = import ./nixpkgs.nix;

  extendLib = lib:
    let
      libOverlays = [
        (import ./dag.nix)
      ] ++ lib.optional (nixusArgs ? libOverlay) nixusArgs.libOverlay;
      libOverlay = lib.foldl' lib.composeExtensions (self: super: {}) libOverlays;
    in lib.extend libOverlay;

  nixusPkgs = import nixpkgs {
    config = {};
    overlays = [
      (self: super: {
        lib = extendLib super.lib;
      })
    ];
    system = nixusArgs.deploySystem or builtins.currentSystem;
  };

  result = nixusPkgs.lib.evalModules {
    modules = [
      modules/options.nix
      modules/deploy.nix
      modules/secrets.nix
      modules/ssh.nix
      modules/public-ip.nix
      modules/dns.nix
      conf
      # Not naming it pkgs to avoid confusion and trouble for overriding scopes
      {
        _module.args.nixus = {
          pkgs = nixusPkgs;
          inherit extendLib;
        };
        _module.args.pkgs = throw "You're trying to access the pkgs argument from a Nixus module, use the nixus argument instead and use nixus.pkgs from that.";
      }
    ];
  };
in result.config.deployScript // result // nixusPkgs.lib.mapAttrs (n: v: v.deployScript) result.config.nodes
