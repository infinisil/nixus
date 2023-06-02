{ config, lib, nixus, ... }:

let
  inherit (lib) types;

  mkScriptCreate = prefix: pools: nixus.pkgs.writeShellScript "deploy-zfs-snap-create" (''
    # get current nixos generation number
    id=$(readlink /nix/var/nix/profiles/system | sed 's/system-\(.*\)-link/\1/')
    # format for the tags, adding a date so there can be multiple for a id
    tag="${prefix}$(date +%Y%m%d%H%M%S)-$id"

    # run snaps for all the defined pools
  '' + (lib.concatMapStringsSep "\n" (x: "echo Taking snapshot for ${x} && zfs snapshot ${x}@$tag") pools));

  mkScriptCleanup = prefix: pools: retention: nixus.pkgs.writeShellScript "deploy-zfs-snap-cleanup" (lib.concatMapStringsSep "\n" (x: ''
    echo Deleting snapshots for ${x} && \
    zfs list -t snapshot -o name ${x} | \
    tail -n +2 | \
    grep '${prefix}' | \
    sort | \
    head -n -${toString retention} | \
    xargs -L 1 --no-run-if-empty zfs destroy
  '') pools);

  nodeOpts = {
    options = {
      pools = lib.mkOption {
        type = types.listOf types.str;
        default = [];
        description = "List of pools to make snapshots for";
      };
      retention = lib.mkOption {
        type = types.int;
        default = 30;
        description = ''
          How many previous snapshots to keep.
          If set to zero, then all snapshots will be deleted upon successful switch.
          If less than zero, the cleanup script will never run.
        '';
      };
    };
  };

  baseOpts = {
    options = {
      nodes = lib.mkOption {
        type = types.attrsOf (types.submodule nodeOpts);
        default = {};
        description = "Nodes to enable snapshotting for";
      };

      prefix = lib.mkOption {
        type = types.str;
        default = "nixus-snap-";
        description = "Prefix to use for snapshots";
      };
    };
  };
in {
  options = {
    zfs-snap = lib.mkOption {
      type = types.submodule baseOpts;
      default = {};
      description = ''
        Used to make ZFS snapshots on nodes, before deploying and switching to configuration.
        Cleanup is done after a successfull switch, where a specified number of previous snapshot will be keept using the retention number.
      '';
      example = {
        nodes = {
          srtoffee = {
            pools = [
              "rpool/safe/persistent"
              "rpool/safe/user"
            ];
            retention = 30;
          };
        };
        prefix = "nixus-snapshots-";
      };
    };
  };

  config.nodes = let
    nnodes = lib.mapAttrs (_: v: {
      deployScriptPhases = let
        scriptCreate = mkScriptCreate config.zfs-snap.prefix v.pools;
        scriptCleanup = mkScriptCleanup config.zfs-snap.prefix v.pools v.retention;
        fullScriptCreate = ''
          echo Copying ZFS snapshotting create script
          nix-copy-closure --to "$HOST" ${scriptCreate}
          echo Taking ZFS snapshots
          ssh "$HOST" ${scriptCreate}
          echo Finished taking snapshots
        '';

        fullScriptCleanup = ''
          echo Copying ZFS snapshotting cleanup script
          nix-copy-closure --to "$HOST" ${scriptCleanup}
          echo Cleaning ZFS snapshots
          ssh "$HOST" ${scriptCleanup}
          echo Finished cleaning snapshots
        '';

      in {
        zfs-snap-create = lib.dag.entryBefore ["switch"] fullScriptCreate;
      } // (if (v.retention >= 0)
            then { zfs-snap-cleanup = lib.dag.entryAfter ["switch"] fullScriptCleanup; }
            else {}
      );
    }) config.zfs-snap.nodes;
  in nnodes;
}
