{ lib, nixus, config, ... }:
let
  inherit (lib) types;

  cfg = config.dns;

  recordTypes = {
    A = {
      options.address = lib.mkOption {
        type = types.str;
      };
      stringCoerce = s: { address = s; };
      toData = v: v.address;
    };
    AAAA = {
      options.address = lib.mkOption {
        type = types.str;
      };
      stringCoerce = s: { address = s; };
      toData = v: v.address;
    };
    NS = {
      options.domain = lib.mkOption {
        type = types.str;
      };
      stringCoerce = s: { domain = s; };
      toData = v: v.domain;
    };
    CNAME = {
      options.domain = lib.mkOption {
        type = types.str;
      };
      stringCoerce = s: { domain = s; };
      toData = v: v.domain;
    };
    CAA = {
      options.flags.issuerCritical = lib.mkOption {
        type = types.bool;
        default = false;
      };
      options.tag = lib.mkOption {
        type = types.enum [ "issue" "issuewild" "iodef" ];
      };
      options.value = lib.mkOption {
        type = types.str;
      };

      stringCoerce = s: { tag = "issue"; value = s; };
      toData = v: "${if v.flags.issuerCritical then "128" else "0"} ${v.tag} \"${lib.escape [ "\"" ] v.value}\"";
    };
    MX = {
      options.preference = lib.mkOption {
        type = types.int;
        default = 10;
      };

      options.domain = lib.mkOption {
        type = types.str;
      };

      stringCoerce = s: { domain = s; };
      toData = v: "${toString v.preference} ${v.domain}";
    };
    TXT = {
      options.text = lib.mkOption {
        type = types.str;
      };

      stringCoerce = s: { text = s; };
      toData = v: "\"${lib.escape [ "\"" ] v.text}\"";
    };
    SRV = {
      options.priority = lib.mkOption {
        type = types.int;
        default = 0;
      };
      options.weight = lib.mkOption {
        type = types.int;
        default = 100;
      };
      options.port = lib.mkOption {
        type = types.port;
      };
      options.target = lib.mkOption {
        type = types.str;
      };
      toData = v: "${toString v.priority} ${toString v.weight} ${toString v.port} ${v.target}";
    };
  };

  /*
  {
    "com" = {
      "infinisil" = {
        _zone = "infinisil.com";
        "sub" = {
          _zone = "sub.infinisil.com";
        };
      };
    };
  }
  */
  zones =
    let
      zoneAttr = zone: lib.setAttrByPath (lib.reverseList (lib.splitString "." zone)) { _zone = zone; };
      result = lib.foldl' (a: e: lib.recursiveUpdate a (zoneAttr e)) {} (lib.attrNames cfg.zones);
    in result;

  getZone = domain:
    assert lib.hasSuffix "." domain;
    let
      go = zones: path:
        if path != [] && zones ? ${lib.head path} then go zones.${lib.head path} (lib.tail path)
        else zones._zone or null;
      elements = lib.reverseList (lib.init (lib.splitString "." domain));
    in go zones elements;

  recordSubmodule = { name, ... }: let zone = getZone name; in {
    options = lib.mapAttrs (_: value:
      let
        module = types.submodule ({ options, config, ... }: {
          options = value.options // {
            ttl = lib.mkOption {
              type = types.int;
            };

            zone = lib.mkOption {
              type = types.str;
            };
          };

          config.zone = lib.mkIf (zone != null) (lib.mkDefault zone);
          config.ttl = lib.mkIf options.zone.isDefined (lib.mkDefault cfg.zones.${config.zone}.ttl);
        });
        type =
          if value ? stringCoerce then
            with types; coercedTo (either str attrs) lib.singleton (listOf (coercedTo str value.stringCoerce module))
          else
            with types; coercedTo attrs lib.singleton (listOf module);
      in lib.mkOption {
        type = type;
        default = [];
      }
    ) recordTypes;
  };

  recordList = lib.concatLists (lib.mapAttrsToList (name: types:
    lib.concatLists (lib.mapAttrsToList (type: records:
      # TODO: Maybe remove duplicates?
      map (record: {
        inherit name type;
        inherit (record) ttl zone;
        data = recordTypes.${type}.toData record;
      }) records
    ) types)
  ) cfg.records);

  recordsByZone = lib.mapAttrs (_: map (record: removeAttrs record [ "zone" ]))
    (lib.groupBy (record: record.zone) recordList);

  soaRecord = zoneCfg:
    let
      inherit (zoneCfg) soa;
      serial = if soa.serial == null then "@NIXUS_ZONE_SERIAL@" else toString soa.serial;
    in {
      name = zoneCfg.name + ".";
      type = "SOA";
      ttl = soa.ttl;
      # TODO: Email escaping and transforming
      data = "${soa.master} ${soa.email} ${serial} ${toString soa.refresh} ${toString soa.retry} ${toString soa.expire} ${toString soa.negativeTtl}";
    };


  nodeConfigs = lib.mapAttrs (node: zones: {
    configuration = {
      networking.firewall.allowedUDPPorts = [ 53 ];
      services.bind = {
        enable = true;
        zones = map (zone: {
          name = zone.name;
          master = true;
          file = zone.zonefile;
        }) zones;
      };
    };

  }) (lib.groupBy (z: z.primaryNode) (lib.attrValues cfg.zones));

in {

  # Records that automatically get set to the appropriate zone
  options.dns.records = lib.mkOption {
    type = types.attrsOf (types.submodule recordSubmodule);
    default = {};
  };

  options.dns.zones = lib.mkOption {
    default = {};
    type = types.attrsOf (types.submodule ({ name, config, ... }: {
      options.name = lib.mkOption {
        type = types.str;
        default = name;
      };

      options.primaryNode = lib.mkOption {
        type = types.str;
        description = ''
          Nixus node for the primary server
        '';
      };

      options.ttl = lib.mkOption {
        type = types.int;
        description = ''
          The TTL to use for records in this zone if the records themselves don't specify it.
        '';
      };

      options.records = lib.mkOption {
        type = types.listOf (types.submodule {
          options.name = lib.mkOption {
            type = types.str;
            description = "Record owner name";
          };
          options.type = lib.mkOption {
            type = types.str;
            description = "Record type";
          };
          options.ttl = lib.mkOption {
            type = types.int;
            description = "Record TTL";
          };
          options.data = lib.mkOption {
            type = types.str;
            description = "Record data";
          };
        });
        default = [ (soaRecord config) ] ++ recordsByZone.${config.name};
      };

      options.zonefile = lib.mkOption {
        type = types.path;
        default = nixus.pkgs.runCommand "${config.name}.zone" {
          contents = lib.concatMapStrings (record:
            "${record.name} ${toString record.ttl} IN ${record.type} ${record.data}\n"
          ) config.records;
          passAsFile = [ "contents" ];
        } ''
          substitute "$contentsPath" "$out" --subst-var-by NIXUS_ZONE_SERIAL "$(date +%s)"
          ${lib.getBin nixus.pkgs.bind}/bin/named-checkzone ${lib.escapeShellArg config.name} "$out"
        '';
      };

      options.soa = {

        ttl = lib.mkOption {
          type = types.int;
          description = "TTL of the SOA record itself.";
        };

        master = lib.mkOption {
          type = types.str;
          description = "The primary master name server for this zone.";
        };

        email = lib.mkOption {
          type = types.str;
          description = "Email address of the person responsible for this zone.";
        };

        # TODO: Don't require these 4 fields unless there are secondary servers
        serial = lib.mkOption {
          type = types.nullOr types.int;
          default = null;
          description = "Serial number for this zone. Should be updated if any records change so that secondary servers are refreshed. Null indicates a serial number automatically generated from the current unix epoch.";
        };

        refresh = lib.mkOption {
          type = types.int;
          description = "Number of seconds after which secondary name servers should query the master for the SOA record, to detect zone changes";
        };

        retry = lib.mkOption {
          type = types.int;
          description = "Number of seconds after which secondary name servers should retry to request the serial number from the master if the master does not respond.";
        };

        expire = lib.mkOption {
          type = types.int;
          description = "Number of seconds after which secondary name servers should stop answering request for this zone if the master does not respond.";
        };

        negativeTtl = lib.mkOption {
          type = types.int;
          description = "How long negative responses should be cached for.";
        };
      };

      config.soa.ttl = lib.mkDefault config.ttl;
    }));
  };

  config.nodes = nodeConfigs;
}
