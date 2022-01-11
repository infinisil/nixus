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
      enable = lib.mkEnableOption "Enable prometheus monitoring for this node";

      name = lib.mkOption {
        type = types.str;
        default = name;
        description = "The name of the name, which is what will be used for prometheus as well";
      };

      # isIPv6 = lib.mkOption {
      #   type = types.bool;
      #   default = false;
      #   description = ''
      #     Indicates if the IP is IPv6, if so it will be enclosed in 
      #   '';
      # };

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
          Remember, if this is given as IPv6, it should be encloused in brackets like so, e.g. [fc00:1234::10].

          This is also the IP address that the prometheus exporters will bind to.
        '';
      };

      ips = lib.mkOption {
        type = types.str;
        description = ''
          TODO(eyJhb): fix this
          fc00:1234::10/128
        '';
      };
    } // secretsOpts;
  };

  primaryNodeOpts = { ... }: {
    options = {
      name = lib.mkOption {
        type = types.str;
      };

      ip = lib.mkOption {
        type = types.str;
        description = "fc00:1234::1/128";
      };
    } // secretsOpts;
  };

  baseOpts = { ... }: {
    options = {
      enable = lib.mkEnableOption "Enable prometheus module";

      primaryNode = lib.mkOption {
        type = types.submodule primaryNodeOpts;
      };

      wireguardPort = lib.mkOption {
        type = types.int;
        default = 12913;
      };

      wireguardListenOn = lib.mkOption {
        type = types.str;
        # default = config.nodes.${options.primaryNode}.networking.public.ipv6;
        description = "What to listen on in regards to Wireguard";
      };

      nodes = lib.mkOption {
        default = {};
        type = types.attrsOf (types.submodule nodeOpts);
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
