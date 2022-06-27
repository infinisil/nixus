{ nixus, lib, config, ... }:
let
  inherit (lib) types;

  globalConfig = config;

  nodeOptions = ({ name, pkgs, config, ... }: {
    options = {
      enable = lib.mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether this node should be deployed
        '';
      };

      preparationPhases = lib.mkOption {
        type = types.dagOf types.lines;
        default = {};
      };

      preparationScript = lib.mkOption {
        type = types.package;
      };

      successTimeout = lib.mkOption {
        type = types.ints.unsigned;
        default = 20;
        description = ''
          How many seconds remote hosts should wait for the success
          confirmation before rolling back.
        '';
      };

      switchTimeout = lib.mkOption {
        type = types.ints.unsigned;
        default = 60;
        description = ''
          How many seconds remote hosts should wait for the system activation
          command to finish before considering it failed.
        '';
      };

      ignoreFailingSystemdUnits = lib.mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether a system activation should be considered successful despite
          failing systemd units.
        '';
      };

      deployFrom = lib.mkOption {
        description = ''
          When deploying from a specific hostname given by the `deployHost` option,
          the node should be connected to using the values specified here.

          This can be used to e.g. indicate that two machines are in the same network,
          so they can deploy to each other using their network-local addresses.
        '';
        example = {
          someDeployHost.host = "172.18.67.46";
          someDeployHost.hasFastConnection = true;
        };
        type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {

          # TODO: What about different ssh ports? Some access abstraction perhaps?
          options.host = lib.mkOption {
            type = lib.types.str;
            example = "root@172.18.67.46";
            description = ''
              How to reach the host via ssh. The username must either be root,
              or a user that is allowed to do passwordless privilege escalation.
              If no username is given, the one that runs the deploy script
              is used.
            '';
          };

          # TODO: Default to true when the address is link-local
          options.hasFastConnection = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Whether there is a fast connection to this host. If true it will cause
              all derivations to be copied directly from the deployment host. If
              false, the substituters are used when possible instead.
            '';
          };

        }));
        default = {};
      };

      host = lib.mkOption {
        type = lib.types.str;
        example = "root@172.18.67.46";
        description = ''
          How to reach the host via ssh. The username must either be root,
          or a user that is allowed to do passwordless privilege escalation.
          If no username is given, the one that runs the deploy script
          is used.
        '';
      };

      hasFastConnection = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether there is a fast connection to this host. If true it will cause
          all derivations to be copied directly from the deployment host. If
          false, the substituters are used when possible instead.
        '';
      };

      closurePaths = lib.mkOption {
        type = lib.types.attrsOf lib.types.package;
        default = {};
        description = ''
          Derivation paths to copy to the host while deploying
        '';
      };

    };

    config = let
      nodeName = name;
      nodeConfig = config;
      switch = pkgs.runCommandNoCC "switch" {
        inherit (nodeConfig) switchTimeout successTimeout ignoreFailingSystemdUnits privilegeEscalationCommand;
        shell = pkgs.runtimeShell;
      } ''
        mkdir -p $out/bin
        substituteAll ${../scripts/switch} $out/bin/switch
        chmod +x $out/bin/switch
      '';
      system = nodeConfig.configuration.system.build.toplevel;
    in {

      # This value is more specific than a generic host, so it should override a host declared by the user with a default priority of 100
      # But it should also still allow the user to mkForce this value, which would be priority 50
      host = lib.mkIf (globalConfig.deployHost != null && nodeConfig.deployFrom ? ${globalConfig.deployHost})
        (lib.mkOverride 75 nodeConfig.deployFrom.${globalConfig.deployHost}.host);

      hasFastConnection = lib.mkIf (globalConfig.deployHost != null && nodeConfig.deployFrom ? ${globalConfig.deployHost})
        (lib.mkOverride 75 nodeConfig.deployFrom.${globalConfig.deployHost}.hasFastConnection);

      deployFrom.${nodeName} = {
        host = "localhost";
        hasFastConnection = true;
      };

      closurePaths = { inherit system switch; };

      # TOOD: Prevent garbage collection of closures until the end of the deploy
      preparationPhases.copyClosure = lib.dag.entryAnywhere ''
        if NIX_SSH_OPTS="-o ServerAliveInterval=15" nix-copy-closure \
          ${if nodeConfig.hasFastConnection then "-s" else ""} \
          --to ${lib.escapeShellArg nodeConfig.host} \
          ${lib.escapeShellArgs (lib.attrValues nodeConfig.closurePaths)}; then
          echo "Successfully copied closure"
        else
          echo -e "\e[31mFailed to copy closure\e[0m"
          exit 1
        fi
      '';

      preparationScript = let
        sortedScripts = (lib.dag.topoSort nodeConfig.preparationPhases).result or (throw "Dependency cycle between scripts in nodes.${nodeName}.preparationPhases");
      in nixus.pkgs.writeShellScript "prepare-${nodeName}"
        (lib.concatMapStringsSep "\n\n" ({ name, data }: ''
          # Phase ${name}
          ${data}
        '') sortedScripts);

    };

  });

in {

  options = {
    defaults = lib.mkOption {
      type = lib.types.submodule nodeOptions;
    };

    deployHost = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };

    deployScript = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
    };
  };

  # TODO: What about requiring either all nodes to succeed or all get rolled back?
  config.deployScript =
    let
      nodesToDeploy = lib.filterAttrs (nodeName: nodeConfig: nodeConfig.enable) globalConfig.nodes;
    in
    # TODO: Handle signals to kill the async command
    nixus.pkgs.writeScript "deploy" ''
      #!${nixus.pkgs.runtimeShell}
      set -euo pipefail

      export SHELLOPTS

      PATH=${lib.makeBinPath
        (with nixus.pkgs; [
          # Without bash being here deployments to localhost do not work. The
          # reason for that is not yet known. Reported in #6.
          bash
          coreutils
          findutils
          gnused
          jq
          openssh
          procps
          rsync
        ])}''${PATH:+:$PATH}

      # Kill all child processes when interrupting/exiting
      trap exit INT TERM
      trap 'for pid in $(jobs -p) ; do kill -- -$pid ; done' EXIT
      # Be sure to use --foreground for all timeouts, therwise a Ctrl-C won't stop them!
      # See https://unix.stackexchange.com/a/233685/214651

      echo "Preparing deployment of all nodes.." >&2

      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (nodeName: nodeConfig:
      ''
        {
          exec > >(sed "s/^/[prep ${nodeName}] /")
          exec 2> >(sed "s/^/[prep ${nodeName}] /" >&2)

          HOST=${lib.escapeShellArg nodeConfig.host}

          echo "Preparing deployment.." >&2

          . ${nodeConfig.preparationScript}
        } &
      '') nodesToDeploy)}

      failedCount=0
      while true; do
        if wait -n; then
          :
        else
          status=$?
          if [[ "$status" -eq 127 ]]; then
            break
          else
            ((++failedCount))
          fi
        fi
      done

      if (( "$failedCount" > 0 )); then
        echo -e "\e[31mFailed to prepare $failedCount nodes\e[0m" >&2
        exit 1
      fi

      echo "Successfully prepared all nodes, now deploying.." >&2

      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (nodeName: nodeConfig: ''
        {
          exec > >(sed "s/^/[deploy ${nodeName}] /")
          exec 2> >(sed "s/^/[deploy ${nodeName}] /" >&2)

          HOST=${lib.escapeShellArg nodeConfig.host}

          echo "Deploying.." >&2

          if ! OLDSYSTEM=$(timeout --foreground 30 \
              ssh -o ControlPath=none -o BatchMode=yes "$HOST" realpath /run/current-system\
            ); then
            echo "Unable to connect to host!" >&2
            exit 1
          fi

          if [ "$OLDSYSTEM" == "${nodeConfig.closurePaths.system}" ]; then
            echo "No deploy necessary" >&2
            exit 0
          fi

          echo "Triggering system switcher..." >&2
          id=$(ssh -o BatchMode=yes "$HOST" exec "${nodeConfig.closurePaths.switch}/bin/switch" start "${nodeConfig.closurePaths.system}")

          echo "Trying to confirm success..." >&2
          active=1
          while [ "$active" != 0 ]; do
            # TODO: Because of the imperative network-setup script, when e.g. the
            # defaultGateway is removed, the previous entry is still persisted on
            # a rebuild switch, even though with a reboot it wouldn't. Maybe use
            # the more modern and declarative networkd to get around this
            set +e
            status=$(timeout --foreground 15 ssh -o ControlPath=none -o BatchMode=yes "$HOST" exec "${nodeConfig.closurePaths.switch}/bin/switch" active "$id")
            active=$?
            set -e
            sleep 1
          done

          case "$status" in
            "success")
              echo "Successfully activated new system!" >&2
              ;;
            "failure")
              echo -e "\e[31mFailed to activate new system! Rolled back to previous one\e[0m" >&2
              echo -e "\e[31mRun the following command to see the logs for the switch:\e[0m" >&2
              echo -e "\e[31mssh ''${HOST@Q} ${builtins.concatStringsSep " " nodeConfig.privilegeEscalationCommand} cat /var/lib/system-switcher/system-$id/log\e[0m" >&2
              exit 1
              # TODO: Try to better show what failed
              ;;
            *)
              echo -e "\e[31mThis shouldn't occur, the status is $status!\e[0m" >&2
              exit 1
              ;;
          esac

        } &
      '') nodesToDeploy)}

      failedCount=0
      while true; do
        if wait -n; then
          :
        else
          status=$?
          if [[ "$status" -eq 127 ]]; then
            break
          else
            ((++failedCount))
          fi
        fi
      done

      if (( "$failedCount" > 0 )); then
        echo -e "\e[31mFailed to deploy $failedCount nodes\e[0m" >&2
        exit 1
      fi

      echo "Successfully deployed all nodes" >&2
    '';

}
