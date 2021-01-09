{ lib, ... }:
let
  inherit (lib) types;
in {

  options.defaults = lib.mkOption {
    type = types.submodule {
      options.configuration = lib.mkOption {
        type = types.submoduleWith {
          modules = [({ options, ... }: {
            options.networking.public = {

              ipv4 = lib.mkOption {
                type = types.str;
                description = "Default public IPv4 address.";
              };
              hasIpv4 = lib.mkOption {
                type = types.bool;
                readOnly = true;
                default = options.networking.public.ipv4.isDefined;
                description = "Whether this node has a public ipv4 address.";
              };

              ipv6 = lib.mkOption {
                type = types.str;
                description = "Default public IPv6 address.";
              };
              hasIpv6 = lib.mkOption {
                type = types.bool;
                readOnly = true;
                default = options.networking.public.ipv6.isDefined;
                description = "Whether this node has a public ipv6 address.";
              };

            };
          })];
        };
      };
    };
  };

}
