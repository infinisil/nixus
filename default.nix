let
  dlib = import ./lib.nix;
in dlib.mkDeployment {
  machines.foo = {
    nixpkgs = fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/tarball/b0bbacb52134a7e731e549f4c0a7a2a39ca6b481";
      sha256 = "15ix4spjpdm6wni28camzjsmhz0gzk3cxhpsk035952plwdxhb67";
    };
    host = "root@138.68.83.114";
    configuration = ./configuration.nix;
  };
}
