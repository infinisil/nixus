{ config, nodes, lib, ... }:

let
  ## configs
  primaryNode = "srtoffee";
  defaultInterval = "30s";
  wgSystemdServiceName = "wireguard-wgprom.service";

  # TODO(eyJhb): make this more pretty
  nodes = lib.mapAttrsToList (_: v: v) config.prometheus.nodes;
  nodesNoPrimary = builtins.filter (node: node.name != primaryNode) nodes;

  ## functions
  mkNodeConfig = node: exporters: { config, ...}: {
    services.prometheus.exporters = mkExporters node exporters;

    # systemd, Requires= After=
    systemd.services = let
      configs = builtins.listToAttrs (lib.forEach exporters (exp: {
        name = "prometheus-${exp.name}-exporter";
        value = {
          requires = [ wgSystemdServiceName ];
          after = [ wgSystemdServiceName ];
          serviceConfig.RestartSec = "1s";
        };
      }));
    in if node.isLocal then {} else configs;
  };

  mkExporters = node: exporters: builtins.listToAttrs (
    lib.forEach exporters (exp: {
      name = exp.name;
      value = {
        enable = true;
        # TODO(eyJhb): here we just assume everything is IPv6
        # unless this works for IPv4 as well?
        listenAddress = "${node.ip}";
      } // exp.options;
    })
  );

  # create batches of nodes
  mkScrapeConfig = jobName: nodes: port: interval: {
    job_name = jobName;
    scrape_interval = interval;

    static_configs = let
      # do something with the nodes
      configs = lib.forEach nodes (node: {
        targets = [ "${node.ip}:${toString port}@${node.name}" ];
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

  # exporters to use
  exporters = [
    # node exporter
    {
      name = "node";
      port = 9100;
      interval = "10s";
      options = {
        enabledCollectors = [
          # extra high (that we should enable)
          "systemd"
          "logind"
          "ethtool"
        ];
      };
    }

    # others??
  ];

in {
  nodes = lib.recursiveUpdate {
    # primary node settings
    "${primaryNode}".configuration = { config, ... }: {

      # prometheus
      services.prometheus = {
        enable = true;
        scrapeConfigs = lib.forEach exporters (exp:
          mkScrapeConfig exp.name nodes exp.port defaultInterval
        );

        exporters = let
          filteredNodes = builtins.filter (node: node.name == primaryNode) nodes;
          val = if (builtins.length filteredNodes) > 0
            then mkExporters (builtins.elemAt filteredNodes 0) exporters
            else {};
        in val;
      };
    };

  } (lib.listToAttrs (lib.forEach nodesNoPrimary (node: lib.nameValuePair node.name { configuration = (mkNodeConfig node exporters); } )));
}
