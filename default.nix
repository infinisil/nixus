import ./build.nix {
  nixpkgs =
    let
      nixpkgsInfo = (builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.nixpkgs.locked;
    in
    fetchTarball {
      url = "https://github.com/NixOS/nixpkgs/archive/${nixpkgsInfo.rev}.tar.gz";
      sha256 = nixpkgsInfo.narHash;
    };
  deploySystem = builtins.currentSystem;
}
