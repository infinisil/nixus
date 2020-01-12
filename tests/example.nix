import ./make-test.nix ({ pkgs, lib, sshKeys, ... }:
let
  deployConfig = nodes: import ../. {
    nodes.target = {
      host = "root@target";
      nixpkgs = pkgs.path;
      configuration = lib.mkMerge (
        nodes.target.config._module.args.modules ++
        nodes.target.config._module.args.baseModules
      );
    };
  };
in {
  nodes = {
    target = { nodes, ... }: {
      # Apparently this doesn't work with pathsInNixDB
      virtualisation.useBootLoader = true;
      virtualisation.pathsInNixDB = [ (deployConfig nodes) ];
      virtualisation.memorySize = 2024;
      virtualisation.diskSize = 8 * 512;

      services.openssh.enable = true;
      users.users.root.openssh.authorizedKeys.keys = [ sshKeys.snakeOilPublicKey ];
      nix.extraOptions = ''
        substitute = false
      '';

    };

    deployer = { nodes, ... }: {
      virtualisation.pathsInNixDB = [ (deployConfig nodes) ];
      virtualisation.memorySize = 2024;
      virtualisation.diskSize = 8 * 512;

      nix.extraOptions = ''
        substitute = false
      '';
    };
  };

  testScript = { nodes, ... }: ''
    start_all()

    deployer.wait_for_unit("multi-user.target")
    target.wait_for_unit("multi-user.target")

    deployer.succeed("nix-store -qR ${deployConfig nodes}")
    # target.succeed("nix-store -qR ${deployConfig nodes}")

    # deployer.succeed("ping target")

    deployer.succeed("mkdir ~/.ssh")
    deployer.succeed(
        "cp ${builtins.toFile "ssh_config" ''
        StrictHostKeyChecking = no
        UserKnownHostsFile = /dev/null
      ''} ~/.ssh/config"
    )
    deployer.succeed(
        "cat ${sshKeys.snakeOilPrivateKey} > ~/.ssh/id_rsa"
    )
    deployer.succeed("chmod 600 ~/.ssh/id_rsa")
    deployer.succeed(
        "ssh -v -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no target echo hello"
    )

    deployer.succeed("${deployConfig nodes}")

    _, res = target.execute("cat /var/lib/system-switcher/system-0/log")
    target.log(res)
  '';
})
