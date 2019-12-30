let
  # TODO: What nixpkgs should be used here?
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
    substituteAll ${scripts/switch} $out/bin/switch
    chmod +x $out/bin/switch
  '';

  optionsModule = { config, ... }: {
    options.machines = lib.mkOption {
      type = types.attrsOf (types.submodule ({ name, config, ... }: {
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

        config.deployScript = pkgs.runCommandNoCC "deploy-${name}" {
          inherit (config) host;
          inherit switch;
          hostname = name;
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
          substituteAll ${scripts/deploy} $out/bin/deploy
          chmod +x $out/bin/deploy
        '';
      }));
      description = "machines";
    };

    options.deployScript = lib.mkOption {
      type = types.package;
      readOnly = true;
    };

    config.deployScript = pkgs.writeScript "deploy" ''
      #!${pkgs.runtimeShell}
      ${lib.concatMapStrings (machine: ''
        ${machine.deployScript}/bin/deploy &
      '') (lib.attrValues config.machines)}
      wait
    '';
  };

in conf:
let
  result = lib.evalModules {
    modules = [
      optionsModule
      conf
    ];
  };
in result.config.deployScript // result
