{ lib, ... }:

rec {
  isIPv6 = str: if (builtins.match "([0-9]+)\\.([0-9]+)\\.([0-9]+)\\.([0-9]+)" str) == null then true else false;

  # adds the correct subnet for either IPv6 or IPv4
  makeIPSubnet = str: if isIPv6 str
                      then "${str}/128"
                      else "${str}/32";

  wrapIP = str: if isIPv6 str
                    then "[${str}]"
                    else str;
}
