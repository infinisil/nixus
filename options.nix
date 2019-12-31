{ config, lib, ... }:
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

  machineOptions = { name, config, ... }: {

    options = {
      # TODO: What about different ssh ports? Some access abstraction perhaps?
      host = lib.mkOption {
        type = lib.types.str;
        example = "root@172.18.67.46";
        description = ''
          How to reach the host via ssh.
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
        # TODO: Specify for merging and inter-machine abstractions and allowing access to configuration values
        type = lib.types.unspecified;
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

    config = let
      system = (import (config.nixpkgs + "/nixos") {
        configuration = {
          imports = [
            config.configuration
            extraConfig
          ];
        };
      }).config.system.build.toplevel;
    in {
      deployScript = pkgs.runCommandNoCC "deploy-${name}" {
        hostname = name;
        inherit (config) host;
        inherit switch;
        systembuild = system;
      } ''
        mkdir -p $out/bin
        substituteAll ${scripts/deploy} $out/bin/deploy
        chmod +x $out/bin/deploy
      '';
    };
  };

in {
  options = {
    machines = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule machineOptions);
      description = "machines";
    };

    deployScript = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
    };

    switchTimeout = lib.mkOption {
      type = types.ints.unsigned;
      default = 10;
      description = ''
        How many seconds remote hosts should wait for the system activation
        command to finish before considering it failed.
      '';
    };

    successTimeout = lib.mkOption {
      type = types.ints.unsigned;
      default = 10;
      description = ''
        How many seconds remote hosts should wait for the success
        confirmation before rolling back.
      '';
    };

  };

  # TODO: What about requiring either all machines to succeed or all get rolled back?
  config.deployScript = pkgs.writeScript "deploy" ''
    #!${pkgs.runtimeShell}
    ${lib.concatMapStrings (machine: ''
      ${machine.deployScript}/bin/deploy &
    '') (lib.attrValues config.machines)}
    wait
  '';
}
