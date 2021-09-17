import ../. {} ({ config, ... }: {

  defaults = { name, ... }: {
    configuration = { lib, ... }: {
      networking.hostName = lib.mkDefault name;
    };

    # Which nixpkgs version we want to use for this node
    nixpkgs = fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/tarball/38431cf21c59a84c0ddedccc0cd66540a550ec26";
      sha256 = "0bi5lkq2a34pij00axsa0l0j43y8688mf41p51b6zyfdzgjgsc42";
    };
  };

  nodes.foo = { lib, config, ... }: {
    # How to reach this node
    host = "root@138.68.83.114";

    # What configuration it should have
    configuration = ./configuration.nix;
  };

})
