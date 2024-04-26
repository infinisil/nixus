{ config, lib, ... }: {

  options.defaults = lib.mkOption {
    type = lib.types.submodule {
      options.configuration = lib.mkOption {
        type = lib.types.submoduleWith {
          specialArgs.unstable = fetchTarball "channel:nixpkgs-unstable";
          modules = [];
        };
      };
    };
  };

  config = {
    defaults = { lib, name, ... }: {
      configuration = {
        networking.hostName = lib.mkDefault name;
      };

      # Which nixpkgs version we want to use for this node
      nixpkgs = lib.mkDefault (fetchTarball {
        url = "https://github.com/NixOS/nixpkgs/tarball/e12483116b3b51a185a33a272bf351e357ba9a99";
        sha256 = "1ili85f34m2ihbcnj1jm7qrsz5ql405zhp07qkngn0gn2c6lyx8l";
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
        url = "https://github.com/NixOS/nixpkgs/tarball/e12483116b3b51a185a33a272bf351e357ba9a99";
        sha256 = "1ili85f34m2ihbcnj1jm7qrsz5ql405zhp07qkngn0gn2c6lyx8l";
      };

      # What configuration it should have
      configuration = ./configuration.nix;
    };
  };

}
