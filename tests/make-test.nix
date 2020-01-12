let
  nixpkgs = import ../nixpkgs.nix;
  pkgs = import nixpkgs {
    config = {};
    overlays = [];
  };
  libTesting = import (nixpkgs + "/nixos/lib/testing-python.nix") {
    system = builtins.currentSystem;
    inherit pkgs;
  };
in f: libTesting.makeTest (f {
  inherit pkgs;
  inherit (pkgs) lib;
  sshKeys = import (nixpkgs + "/nixos/tests/ssh-keys.nix") pkgs;
})
