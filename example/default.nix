import ../. ({ config, ... }: {

  defaults = { name, ... }: {
    configuration = { lib, ... }: {
      networking.hostName = lib.mkDefault name;
    };

    # Which nixpkgs version we want to use for this node
    nixpkgs = fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/tarball/a06925d8c608d7ba1d4297dc996c187c37c6b7e9";
      sha256 = "0xy6rimd300j5bdqmzizs6l71x1n06pfimbim1952fyjk8a3q4pr";
    };
  };

  nodes.foo = { lib, config, ... }: {
    # How to reach this node
    host = "root@138.68.83.114";

    secrets.password.file = ./secret;

    # What configuration it should have
    configuration = lib.mkMerge [
      ./configuration.nix
      { environment.etc.password.source = config.secrets.password.file; }
    ];
  };

})
