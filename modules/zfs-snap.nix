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

  mkScriptCleanup = prefix: pools: retention: nixus.pkgs.writeShellScript "deploy-zfs-snap-cleanup" (lib.concatMapStringsSep "\n" (x: "echo Deleting snapshots for ${x} && zfs list -t snapshot ${x} -o name | tail -n +2 | grep -i '${prefix}' | sort | head -n -${toString retention} | xargs -L 1 --no-run-if-empty zfs destroy") pools);

  nodeOpts = {
    options = {
      pools = lib.mkOption {
        type = types.listOf types.str;
        default = [];
        description = "List of pools to make snapshots for, ie. rpool/safe/persistent";
      };
      retention = lib.mkOption {
        type = types.int;
        default = 30;
        description = "How many previous ZFS snapshots to keep";
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
        Used to make ZFS snapshots on host, before deploying and switching to configuration.
        Cleanup is also done, where a specified number of previous snapshot can be keept, before they are removed.
      '';
    };
  };

  config.nodes = let
    nnodes = lib.mapAttrs (_: v: {
      deployScriptPhases.zfs-snap-create = let
        script = mkScriptCreate config.zfs-snap.prefix v.pools;
      in lib.dag.entryBefore ["switch"] ''
        echo Copying ZFS snapshotting create script
        nix-copy-closure --to "$HOST" ${script}
        echo Taking ZFS snapshots
        ssh "$HOST" ${script}
        echo Finished taking snapshots
      '';

      deployScriptPhases.zfs-snap-cleanup = let
        script = mkScriptCleanup config.zfs-snap.prefix v.pools v.retention;
      in lib.dag.entryAfter ["switch"] ''
        echo Copying ZFS snapshotting cleanup script
        nix-copy-closure --to "$HOST" ${script}
        echo Cleaning ZFS snapshots
        ssh "$HOST" ${script}
        echo Finished cleaning snapshots
      '';
    }) config.zfs-snap.nodes;
  in nnodes;
}
