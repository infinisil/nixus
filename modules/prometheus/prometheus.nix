{ config, lib, nixus, ... }:

let
  utils = nixus.pkgs.callPackage ./utils.nix {};

  ## configs
  promNodes = lib.attrValues config.prometheus.nodes;
  primaryNode = lib.elemAt (lib.filter (v: v.isPrimary) promNodes) 0;
  promNodesNoPrimary = lib.filter (node: node.name != primaryNode.name) promNodes;
  exporters = config.prometheus.exporters;
  wgSystemdServiceName = "wireguard-${config.prometheus.wireguardInterfaceName}.service";

  ## functions
  mkNodeConfig = node: exporters: { config, ...}: {
    services.prometheus.exporters = mkExporters node exporters;

    # systemd, Requires= After=
    systemd.services = let
      configs = lib.listToAttrs (lib.forEach exporters (exp: {
        name = "prometheus-${exp.name}-exporter";
        value = {
          requires = [ wgSystemdServiceName ];
          after = [ wgSystemdServiceName ];
          serviceConfig.RestartSec = "1s";
        };
      }));
    in if node.isLocal then {} else configs;
  };

  mkExporters = node: exporters: lib.listToAttrs (
    lib.forEach exporters (exp: {
      name = exp.name;
      value = {
        enable = true;
        listenAddress = utils.wrapIP node.ip;
      } // exp.options;
    })
  );

  # create batches of nodes
  mkScrapeConfig = name: exp: {
    job_name = name;
    scrape_interval = exp.scrapeInterval;

    static_configs = let
      # try to get the correct port to use.
      # if a port is defined in options, then use that
      # otherwise use the default port based on the primary node configuration
      port = if exp.options ? port
             then exp.options.port
             else config.nodes.${primaryNode.name}.configuration.services.prometheus.exporters.${exp.name}.port;

      # do something with the nodes
      configs = lib.forEach promNodes (node: {
        targets = [ "${utils.wrapIP node.ip}:${toString port}@${node.name}" ];
        # labels.alias = x.name;
      });
    in configs;

    relabel_configs = [
      {
        source_labels = [ "__address__" ];
        regex = ".*@(.*)";
        target_label = "instance";
      }
      {
        source_labels = [ "__address__" ];
        regex = "(.*)@.*";
        target_label = "__address__";
      }
    ];
  };
in {
  config = lib.mkIf config.prometheus.enable {
    nodes = lib.recursiveUpdate {
      # primary node settings
      ${primaryNode.name}.configuration = { config, ... }: {
        services.prometheus = {
          enable = true;
          scrapeConfigs = lib.attrValues (lib.mapAttrs (name: exp:
            mkScrapeConfig name exp
          ) exporters);

          exporters = let
            filteredNodes = lib.filter (node: node.name == primaryNode.name) promNodes;
            val = if (lib.length filteredNodes) > 0
              then mkExporters (lib.elemAt filteredNodes 0) (lib.attrValues exporters)
              else {};
          in val;
        };
      };

      # all other nodes configuration
    } (lib.listToAttrs (lib.forEach promNodesNoPrimary (node: lib.nameValuePair node.name { configuration = (mkNodeConfig node (lib.attrValues exporters)); } )));
  };
}
