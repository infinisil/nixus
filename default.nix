{ pkgs ? import <nixpkgs> {} }: {

  system = (import (pkgs.path + "/nixos") {
    configuration = ./configuration.nix;
  }).config.system.build.toplevel;

}
