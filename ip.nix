final: prev: {
  ip = {
    parseIp = str: map final.toInt (builtins.match "([0-9]+)\\.([0-9]+)\\.([0-9]+)\\.([0-9]+)" str);
    prettyIp = final.concatMapStringsSep "." toString;

    cidrToMask =
      let
        # Generate a partial mask for an integer from 0 to 7
        #   part 1 = 128
        #   part 7 = 254
        part = n:
          if n == 0 then 0
          else part (n - 1) / 2 + 128;
      in cidr:
        let
          # How many initial parts of the mask are full (=255)
          fullParts = cidr / 8;
        in final.genList (i:
          # Fill up initial full parts
          if i < fullParts then 255
          # If we're above the first non-full part, fill with 0
          else if fullParts < i then 0
          # First non-full part generation
          else part (final.mod cidr 8)
        ) 4;

    parseSubnet = str:
      let
        splitParts = builtins.split "/" str;
        givenIp = final.ip.parseIp (final.elemAt splitParts 0);
        cidr = final.toInt (final.elemAt splitParts 2);
        mask = final.ip.cidrToMask cidr;
        baseIp = final.zipListsWith final.bitAnd givenIp mask;
        range = {
          from = baseIp;
          to = final.zipListsWith (b: m: 255 - m + b) baseIp mask;
        };
        check = ip: baseIp == final.zipListsWith (b: m: final.bitAnd b m) ip mask;
        warn = if baseIp == givenIp then final.id else final.warn
          ( "subnet ${str} has a too specific base address ${final.ip.prettyIp givenIp}, "
          + "which will get masked to ${final.ip.prettyIp baseIp}, which should be used instead");
      in warn {
        inherit baseIp cidr mask range check;
        subnet = "${final.ip.prettyIp baseIp}/${toString cidr}";
      };
  };
}
