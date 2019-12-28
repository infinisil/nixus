# Auto-rollback deployer

This is a work-in-progress deployment tool I'm developing for [https://niteo.co/](Niteo). The main distinguishing feature as of now is that it automatically does a rollback if the new system failed in some ways. Notably it protects against:

- Messing up the network config
- Removing your SSH key from the authorized keys
- The activation script failing in any way
- The boot activation failing in any way
- The system crashing during the deployment

## How to use it

Note: This is just to demonstrate, this will certainly change in the future

Write a file like the `default.nix`, then build the deployment script and call it
```
$ nix-build -A config.machines.foo.deployScript
/nix/store/rjxa2f4fhc1pc482rm6498j3mrc69q1v-deploy
$ result/bin/deploy
Copying closure to host..
copying 4 paths...
copying path '/nix/store/2mbwwp1ya19a69yicbn2mpnf573iaa9f-unit-nscd.service' to 'ssh://ssh://root@138.68.83.114'...
copying path '/nix/store/wy55d577d14vzpb88pdqlr1m3qxf0ayg-system-units' to 'ssh://ssh://root@138.68.83.114'...
copying path '/nix/store/isnkndlndlsj4pq9mscy0fp9cs5hszwf-etc' to 'ssh://ssh://root@138.68.83.114'...
copying path '/nix/store/wc6f73r96dysmclns6gpan9v3nx8zn5a-nixos-system-test-20.03pre-git' to 'ssh://ssh://root@138.68.83.114'...
Triggering system switcher..
Trying to confirm success...
Successfully activated new system!
```

Here is an example of a messed up network config:
```
Copying closure to host..
Triggering system switcher..
Trying to confirm success................
Failed to activate new system! Rolled back to previous one
```

## How it works

The basic idea is to first do a `nixos-rebuild test` on the target machine, after which we try to connect to the machine again to confirm that it worked. If we can't make this confirmation, a rollback is issued.
