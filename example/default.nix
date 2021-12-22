import ../. {} ({ config, ... }: {

  defaults = { name, ... }: {
    configuration = { lib, ... }: {
      networking.hostName = lib.mkDefault name;
    };

    # Which nixpkgs version we want to use for this node
    nixpkgs = fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/tarball/81cef6b70fb5d5cdba5a0fef3f714c2dadaf0d6d";
      sha256 = "1mj9psy1hfy3fbalwkdlyw3jmc97sl9g3xj1xh8dmhl68g0pfjin";
    };
  };

  nodes.foo = { lib, config, ... }: {
    # How to reach this node
    host = "root@138.68.83.114";

    # What configuration it should have
    configuration = ./configuration.nix;
  };

})
