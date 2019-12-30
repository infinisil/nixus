conf: let
  # TODO: What nixpkgs should be used here?
  result = (import <nixpkgs/lib>).evalModules {
    modules = [
      ./options.nix
      conf
    ];
  };
in result.config.deployScript // result
