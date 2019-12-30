import ../. {

  machines."foo.example.com" = {
    # How to reach this machine
    host = "root@138.68.83.114";

    # Which nixpkgs version we want to use for this machine
    nixpkgs = fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/tarball/a06925d8c608d7ba1d4297dc996c187c37c6b7e9";
      sha256 = "0xy6rimd300j5bdqmzizs6l71x1n06pfimbim1952fyjk8a3q4pr";
    };

    # What configuration it should have
    configuration = ./configuration.nix;
  };

}
