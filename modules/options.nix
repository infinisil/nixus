{ options, config, lib, ... }:
let
  inherit (lib) types;

  extraConfig = { lib, ... }: {
    # By default the sshd service doesn't stop when changed so you don't lose connection to it when misconfigured
    # But in Nixus we want to detect a misconfiguration since we can rollback in that case
    systemd.services.${if config.services.openssh.startWhenNeeded then "sshd@" else "sshd"}.stopIfChanged = lib.mkForce true;
  };

  pkgsModule = nixpkgs: { lib, config, ... }: {
    config.nixpkgs.system = lib.mkDefault builtins.currentSystem;
    # Not using nixpkgs.pkgs because that would apply the overlays again
    config._module.args.pkgs = lib.mkDefault (import nixpkgs {
      inherit (config.nixpkgs) config overlays localSystem crossSystem;
    });

    # Export the pkgs arg because we use it outside the module
    # See https://github.com/NixOS/nixpkgs/pull/82751 why that's necessary
    options._pkgs = lib.mkOption {
      readOnly = true;
      internal = true;
      default = config._module.args.pkgs;
    };
  };

  topconfig = config;

  nodeOptions = { name, config, ... }: {

    options = {

      enabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether this node should be included in the build.
        '';
      };

      nixpkgs = lib.mkOption {
        type = lib.types.path;
        example = lib.literalExample ''
          fetchTarball {
            url = "https://github.com/NixOS/nixpkgs/tarball/a06925d8c608d7ba1d4297dc996c187c37c6b7e9";
            sha256 = "0xy6rimd300j5bdqmzizs6l71x1n06pfimbim1952fyjk8a3q4pr";
          }
        '';
        description = ''
          The path to the nixpkgs version to use for this host.
        '';
      };

      configuration = lib.mkOption {
        type =
          let baseModules = import (config.nixpkgs + "/nixos/modules/module-list.nix");
          in types.submoduleWith {
            specialArgs = {
              lib = (import (config.nixpkgs + "/lib")).extend (import ../dag.nix);
              # TODO: Move these to not special args
              nodes = lib.mapAttrs (name: value: value.configuration) topconfig.nodes;
              inherit name baseModules;
              modulesPath = config.nixpkgs + "/nixos/modules";
            };
            modules = baseModules ++ [ (pkgsModule config.nixpkgs) extraConfig ];
          };
        default = {};
        example = lib.literalExample ''
          {
            imports = [ ./hardware-configuration.nix ];
            boot.loader.grub.device = "/dev/sda";
            networking.hostName = "test";
          }
        '';
        description = ''
          The NixOS configuration for this host.
        '';
      };

    };

    config = {
      _module.args.pkgs = config.configuration._pkgs;
    };
  };

in {

  options = {
    defaults = lib.mkOption {
      type = lib.types.submodule nodeOptions;
      example = lib.literalExample ''
        { name, ... }: {
          networking.hostName = name;
        }
      '';
      description = ''
        Configuration to apply to all nodes.
      '';
    };

    nodes = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule (options.defaults.type.functor.payload.modules ++ options.defaults.definitions));
      description = "nodes";
    };

  };
}
