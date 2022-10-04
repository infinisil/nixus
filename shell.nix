let
  sources = import ./nix/sources.nix;
  pkgs = import sources.nixpkgs {
    config = {};
    overlays = [];
  };
in pkgs.mkShell {
  nativeBuildInputs = [
    pkgs.niv
  ];
}

