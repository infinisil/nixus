{ lib, pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader.timeout = 40;
  boot.loader.grub.device = "/dev/vda";
  boot.kernelPackages = pkgs.linuxPackages_latest;

  i18n.consoleUseXkbConfig = true;
  services.xserver.xkbVariant = "dvp";

  networking = {
    useNetworkd = true;
    useDHCP = false;
    nameservers = [ "1.1.1.1" "1.0.0.1" ];
    defaultGateway = "138.68.80.1";
    usePredictableInterfaceNames = false;
    interfaces.eth0 = {
      ipv4.addresses = [{
        address = "138.68.83.114";
        prefixLength = 20;
      }];
    };
  };

  services.openssh.enable = true;
  services.openssh.permitRootLogin = "yes";

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHjY4cuUk4IWgBgnEJSULkIHO+njUmIFP+WSWy7IobBs infinisil@vario"
  ];


  system.stateVersion = "19.09";
}
