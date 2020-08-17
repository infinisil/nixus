import ../. {} ({ config, ... }: {

  defaults = { name, ... }: {
    configuration = { lib, ... }: {
      networking.hostName = lib.mkDefault name;
    };

    # Which nixpkgs version we want to use for this node
    nixpkgs = fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/tarball/16fc531784ac226fb268cc59ad573d2746c109c1";
      sha256 = "0qw1jpdfih9y0dycslapzfp8bl4z7vfg9c7qz176wghwybm4sx0a";
    };
  };

  nodes.foo = { lib, config, ... }: {
    # How to reach this node
    host = "root@138.68.83.114";

    # What configuration it should have
    configuration = ./configuration.nix;
  };

})
