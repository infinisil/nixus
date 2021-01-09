{ lib, config, ... }:

let
  inherit (lib) types;

  wireguardNetworks = lib.filterAttrs (name: net: net.enable && net.backend == "wireguard") config.vpn.networks;

in {

  options.vpn.networks = lib.mkOption {
    type = types.attrsOf (types.submodule {

      options.backend = lib.mkOption {
        type = types.enum [ "wireguard" ];
      };

      options.server.wireguard.publicKey = lib.mkOption {
        type = types.str;
      };

      options.server.wireguard.privateKeyFile = lib.mkOption {
        type = types.path;
      };

      options.clients = lib.mkOption {
        type = types.attrsOf (types.submodule {

          options.wireguard.publicKey = lib.mkOption {
            type = types.str;
          };

          options.wireguard.privateKeyFile = lib.mkOption {
            type = types.path;
          };

        });
      };

      config.server.port = lib.mkDefault 51820;

    });
  };

  config.nodes = lib.mkMerge (lib.flip lib.mapAttrsToList wireguardNetworks (name: net:
  let
    interface = "nixus-${name}";
    parsedSubnet = lib.ip.parseSubnet net.subnet;
  in {

    ${net.server.node}.configuration = lib.mkMerge [
      {

        networking.firewall.allowedUDPPorts = [ net.server.port ];

        # Needed for both networking between clients and for client -> internet
        boot.kernel.sysctl."net.ipv4.conf.${interface}.forwarding" = true;

        networking.wg-quick.interfaces.${interface} = {
          address = [ "${net.server.subnetIp}/${toString parsedSubnet.cidr}" ];
          listenPort = net.server.port;
          privateKeyFile = net.server.wireguard.privateKeyFile;

          peers = lib.mapAttrsToList (clientNode: clientValue: {
            publicKey = clientValue.wireguard.publicKey;
            allowedIPs = [ "${clientValue.subnetIp}/32" ];
          }) net.clients;
        };
      }

      (lib.mkIf net.server.internetGateway {

        networking.nat = {
          enable = true;
          externalInterface = net.server.internetGatewayInterface;
          internalInterfaces = [ interface ];
        };

        networking.wg-quick.interfaces.${interface} = {
          postUp = ''
            iptables -t nat -A POSTROUTING -j MASQUERADE \
              -s ${parsedSubnet.subnet} -o ${net.server.internetGatewayInterface}
          '';

          postDown = ''
            iptables -t nat -D POSTROUTING -j MASQUERADE \
              -s ${parsedSubnet.subnet} -o ${net.server.internetGatewayInterface}
          '';
        };

      })
    ];
  }

  // lib.flip lib.mapAttrs net.clients (clientNode: clientValue: {

    configuration.networking.wg-quick.interfaces.${interface} = {
      address = [ "${clientValue.subnetIp}/${toString parsedSubnet.cidr}" ];
      privateKeyFile = clientValue.wireguard.privateKeyFile;

      peers = lib.singleton {
        publicKey = net.server.wireguard.publicKey;
        allowedIPs = if clientValue.internetGateway
          then [ "0.0.0.0/0" ]
          else [ parsedSubnet.subnet ];
        endpoint = "${config.nodes.${net.server.node}.configuration.networking.public.ipv4}:${toString net.server.port}";
        persistentKeepalive = 25;
      };
    };

  })));

}
