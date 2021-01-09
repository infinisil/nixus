{ lib, ... }:
let
  inherit (lib) types;

  /*
  TODO: Validate subnet IPs and/or allow numbering of them (e.g. server gets 1st IP in range, client A gets 2nd, etc.)
  */
in {

  imports = [
    ./wireguard.nix
  ];

  options.vpn.networks = lib.mkOption {
    default = {};
    type = types.attrsOf (types.submodule ({ config, ... }: let netConfig = config; in {

      options = {

        enable = lib.mkOption {
          type = types.bool;
          default = true;
        };

        backend = lib.mkOption {
          type = types.enum [];
        };

        subnet = lib.mkOption {
          type = types.str;
        };

        server = {
          node = lib.mkOption {
            type = types.str;
          };

          port = lib.mkOption {
            type = types.port;
          };

          subnetIp = lib.mkOption {
            type = types.str;
          };

          internetGateway = lib.mkOption {
            type = types.bool;
            default = false;
          };

          internetGatewayInterface = lib.mkOption {
            type = types.str;
          };
        };

        clients = lib.mkOption {
          default = {};
          type = types.attrsOf (types.submodule {

            options.enable = lib.mkOption {
              type = types.bool;
              default = true;
            };

            options.subnetIp = lib.mkOption {
              type = types.nullOr types.str;
            };

            options.internetGateway = lib.mkOption {
              type = types.bool;
              default = netConfig.server.internetGateway;
              defaultText = "netConfig.server.internetGateway";
            };

          });
        };

      };

    }));
  };
}
