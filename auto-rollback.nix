{ lib, config, pkgs, ... }:
let
  switch = pkgs.runCommandNoCC "switch" {
    # TODO: Make NixOS module for this
    switchTimeout = 120;
    successTimeout = 10;
    nix = lib.getBin config.nix.package;
  } ''
    mkdir -p $out/bin
    substituteAll ${./activator} $out/bin/switch
    chmod +x $out/bin/switch
  '';
in {

  environment.systemPackages = [
    switch
  ];

  systemd.services."system-switcher" = {
    # TODO: Are these needed?
    restartIfChanged = false;
    unitConfig.X-StopOnRemoval = false;
    serviceConfig = {
      StateDirectory = "system-switcher";
      ExecStart = "${switch}/bin/switch run";
    };
  };

}
