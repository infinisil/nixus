{ config, ... }: {

  defaults = { lib, name, ... }: {
    configuration = {
      networking.hostName = lib.mkDefault name;
    };

    # Which nixpkgs version we want to use for this node
    nixpkgs = lib.mkDefault (fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/tarball/81cef6b70fb5d5cdba5a0fef3f714c2dadaf0d6d";
      sha256 = "1mj9psy1hfy3fbalwkdlyw3jmc97sl9g3xj1xh8dmhl68g0pfjin";
    });
  };

  nodes.foo = { lib, config, ... }: {
    # How to reach this node
    host = "root@172.20.83.114";

    # What configuration it should have
    configuration = ./configuration.nix;
  };

  nodes.legacyNixpkgs = { lib, config, ... }: {
    # How to reach this node
    host = "root@172.20.83.115";

    nixpkgs = fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/tarball/38431cf21c59a84c0ddedccc0cd66540a550ec26";
      sha256 = "0bi5lkq2a34pij00axsa0l0j43y8688mf41p51b6zyfdzgjgsc42";
    };

    # What configuration it should have
    configuration = ./configuration.nix;
  };

}
