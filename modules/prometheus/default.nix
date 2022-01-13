{ config, lib, ... }:

let
  inherit (lib) types;

  secretsOpts = {
    # secret files
    wgPublicKey = lib.mkOption {
      type = types.path;
    };
    wgPrivateKey = lib.mkOption {
      type = types.path;
    };
    wgPresharedKey = lib.mkOption {
      type = types.path;
    };
  };

  nodeOpts = { name, config, ... }: {
    options = {
      enable = lib.mkOption {
        type = types.bool;
        default = true;
        description = "Enable prometheus monitoring for this node";
      };

      name = lib.mkOption {
        type = types.str;
        default = name;
        description = "The name of the name, which is what will be used for prometheus as well";
      };

      isPrimary = lib.mkOption {
        type = types.bool;
        default = false;
        description = ''
          Indicates if this node is the primary node, which will run prometheus as well as Wireguard.
        '';
      };

      isLocal = lib.mkOption {
        type = types.bool;
        default = false;
        description = ''
          Indicates of the device is attached to the same network as the prometheus instance

          false indicates that the node is not on the same network, and will then use a wireguard
          tunnel to connect to the instance.

          true indicates that the node is on the same network, ind will then not use a wireguard
          tunnel to connect to the instance.
        '';
      };

      ip = lib.mkOption {
        type = types.str;
        description = ''
          The IP address of the node, that the prometheus instance should try to contact to scrape.

          For non-local nodes, this is also the IP that will be used for the Wireguard tunnel.

          This is also the IP address that the prometheus exporters will bind to.
        '';
      };
    } // secretsOpts;
  };

  baseOpts = { ... }: {
    options = {
      enable = lib.mkEnableOption "Enable prometheus module";

      wireguardPort = lib.mkOption {
        type = types.int;
        default = 12913;
      };

      wireguardListenOn = lib.mkOption {
        type = types.str;
        description = "What to listen on in regards to Wireguard";
      };

      wireguardInterfaceName = lib.mkOption {
        type = types.str;
        default = "wgprom";
        description = "Name used for Wireguard interface";
      };

      nodes = lib.mkOption {
        type = types.attrsOf (types.submodule nodeOpts);
        default = {};
        apply = x: let
            # only use enabledNodes
            enabledNodes = lib.filterAttrs (_: v: v.enable ) x;
            nodesFilteredPrimary = lib.attrValues (lib.filterAttrs (_: v: v.isPrimary) enabledNodes);
            primaryNode = builtins.elemAt nodesFilteredPrimary 0;
          in if builtins.length nodesFilteredPrimary == 0
                then throw "there needs to be at least one primary node"
                else enabledNodes // { "${primaryNode.name}" = primaryNode // { isLocal = true; }; };
      };
    };
  };
in {
  imports = [
    ./wireguard.nix
    ./prometheus.nix
  ];

  options.prometheus = lib.mkOption {
    type = types.submodule baseOpts;
    default = {};
  };
}
