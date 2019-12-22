{ lib, config, pkgs, ... }: {
  /*
  Things to consider:
  - What happens if we receive another system when one is being tested already?
  */
  /*
  Idea:
  - First nixos-rebuild test -> auto-reverts when crash
  - When activated it starts the timer thing
  - After timer runs out without confirmation, nixos-rebuild test to the old (still-working) generation
  - After timer runs out again without confirmation, reboot -> should boot into still-working generation
  - If confirmation received, set the new generation to be the default

  - Make a log of good system builds? Because..? No reason, we know all the good builds from nix-env

  Implementation:
  - Server runs a socket, accepting system paths to test/activate
  - When received, do
    - set oldpath=$(realpath /run/current-system)
    - $path/bin/switch-to-configuration test
    - start timer process

  Do we need a systemd service or can it just be a command?
  Advantages of systemd service:
  - Prevent multiple testings at the same time, but this can be achieved with a lock file too
  - Logs the process persistently, can still log it really
  - Rollback still happens even if ssh disconnects or whatever ??
  - Cleaner, logs together, status directory maybe, is a system service kind o
  - Easy

  Advantages of command:
  - Easy to follow progress

  Where to report status?

  Communication?

  Make sure to use -o ControlMaster=no for the success confirmation
  */


  systemd.sockets.system-switcher = {
    #after = ??
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenFIFO = "%t/system-switcher-system";
    };
  };
  systemd.services.system-switcher = {
    restartIfChanged = false;
    unitConfig.X-StopOnRemoval = false;
    serviceConfig = {
      Type = "oneshot";

      RuntimeDirectory = "system-tester";
      StandardInput = "socket";
      StandardOutput = "journal";
      ExecStart = pkgs.substituteAll {
        src = ./activator;
        isExecutable = true;
        switchTimeout = 120;
        #successTimeout = 120;
        successTimeout = 30;
        nix = lib.getBin config.nix.package;
      };
    };
  };

}
