let
  pkgs = import <nixpkgs> {};
  inherit (pkgs) lib;
  inherit (lib) types;

  extraConfig = { lib, ... }: {
    systemd.services.sshd.stopIfChanged = lib.mkForce true;
  };

  switch = pkgs.runCommandNoCC "switch" {
    # TODO: Make NixOS module for this
    switchTimeout = 120;
    successTimeout = 10;
  } ''
    mkdir -p $out/bin
    substituteAll ${./activator} $out/bin/switch
    chmod +x $out/bin/switch
  '';

  optionsModule = {
    options.machines = lib.mkOption {
      type = types.attrsOf (types.submodule ({ config, ... }: {
        options.host = lib.mkOption {
          type = types.str;
        };

        options.nixpkgs = lib.mkOption {
          type = types.path;
          description = "nixpkgs to use";
        };

        options.configuration = lib.mkOption {
          # TODO: Specify for merging and inter-machine abstractions
          type = types.unspecified;
        };

        options.deployScript = lib.mkOption {
          type = types.package;
          readOnly = true;
        };

        config.deployScript = pkgs.runCommandNoCC "deploy" {
          inherit (config) host;
          inherit switch;
          # TODO: Pass lib as specialArgs
          systembuild = (import (config.nixpkgs + "/nixos") {
            configuration = {
              imports = [
                config.configuration
                extraConfig
              ];
            };
          }).config.system.build.toplevel;
        } ''
          mkdir -p $out/bin
          substituteAll ${./deploy} $out/bin/deploy
          chmod +x $out/bin/deploy
        '';
      }));
      description = "machines";
    };
  };

in {

  mkDeployment = conf: lib.evalModules {
    modules = [
      optionsModule
      conf
    ];
  };

}
