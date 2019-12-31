{ options, config, lib, ... }:
let
  # TODO: How to make this pure?
  pkgs = import <nixpkgs> {};
  inherit (lib) types;

  switch = pkgs.runCommandNoCC "switch" {
    inherit (config) switchTimeout successTimeout;
  } ''
    mkdir -p $out/bin
    substituteAll ${scripts/switch} $out/bin/switch
    chmod +x $out/bin/switch
  '';

  extraConfig = { lib, ... }: {
    systemd.services.sshd.stopIfChanged = lib.mkForce true;
  };

  pkgsModule = nixpkgs: { lib, config, ... }: {
    nixpkgs.system = lib.mkDefault builtins.currentSystem;
    # Not using nixpkgs.pkgs because that would apply the overlays again
    _module.args.pkgs = lib.mkDefault (import nixpkgs {
      inherit (config.nixpkgs) config overlays localSystem crossSystem;
    });
  };

  topconfig = config;

  machineOptions = { name, config, ... }: {

    options = {

      enabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether this machine should be included in the build.
        '';
      };

      # TODO: What about different ssh ports? Some access abstraction perhaps?
      host = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        example = "root@172.18.67.46";
        description = ''
          How to reach the host via ssh. Deploying is disabled if null.
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
              lib = import (config.nixpkgs + "/lib");
              # TODO: Move these to not special args
              machines = lib.mapAttrs (name: value: value.configuration) topconfig.machines;
              inherit name baseModules;
            };
            modules = baseModules ++ [ (pkgsModule config.nixpkgs) ];
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

      deployScript = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        description = ''
          The path to the script to deploy all hosts.
        '';
      };

    };

    config = {
      deployScript = pkgs.runCommandNoCC "deploy-${name}" {
        hostname = name;
        host = if config.host == null then "" else config.host;
        inherit switch;
        systembuild = config.configuration.system.build.toplevel;
      } ''
        mkdir -p $out/bin
        substituteAll ${scripts/deploy} $out/bin/deploy
        chmod +x $out/bin/deploy
      '';
    };
  };

in {
  options = {
    default = lib.mkOption {
      type = lib.types.submodule machineOptions;
      example = lib.literalExample ''
        { name, ... }: {
          networking.hostName = name;
        }
      '';
      description = ''
        Configuration to apply to all machines.
      '';
    };

    machines = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ([ machineOptions ] ++ options.default.definitions));
      description = "machines";
    };

    deployScript = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
    };

    switchTimeout = lib.mkOption {
      type = types.ints.unsigned;
      default = 60;
      description = ''
        How many seconds remote hosts should wait for the system activation
        command to finish before considering it failed.
      '';
    };

    successTimeout = lib.mkOption {
      type = types.ints.unsigned;
      default = 20;
      description = ''
        How many seconds remote hosts should wait for the success
        confirmation before rolling back.
      '';
    };

  };

  # TODO: What about requiring either all machines to succeed or all get rolled back?
  config.deployScript = pkgs.writeScript "deploy" ''
    #!${pkgs.runtimeShell}
    ${lib.concatMapStrings (machine: lib.optionalString machine.enabled ''

      ${machine.deployScript}/bin/deploy &
    '') (lib.attrValues config.machines)}
    wait
  '';
}
