# Nixus: Experimental deployment tool for multiple NixOS systems

This is an experimental deployment tool I'm using for my own systems.

## Features

### Multi-host modules

Nixus is roughly based on a module system evaluation of type `attrsOf nixos`.
That is, the module system is used for the entire evaluation, and not just for each individual NixOS machine.
This most notably allows writing options that influence the configuration of multiple machines.

These abstraction modules can be written for personal use by anybody, just like any user can write their own NixOS modules.

#### Example: SSH access

The [SSH access module](./modules/ssh.nix), included by default,
enables an easy way to configure ssh access between users on different machines.
After configuring the host and user keys, a definition like this:

```nix
ssh.access.host1.keys.someHost1User.hasAccessTo.host2.someHost2User = true;
```

Will grant `someHost1User@host1` SSH access to `someHost2User@host2`.
More concretely, it does two things:
- Adds `someHost1User`'s SSH key from `host1` to the authorized keys list of `someHost2User` on `host2`
- Adds `host2`'s SSH host key to the known hosts list on `host1`.

This means that when logged into `someHost1User@host1`, one can run `ssh someHost2User@host2` without any extra steps required.

For a more complete example, see [my own configuration](https://github.com/infinisil/system/blob/4295f8e8646d8646406604c48e38be69b0759ced/config/multimods/ssh-access.nix).

#### Example: VPN network

The [VPN module](./modules/vpn), included by default,
enables an easy way to configure a VPN network between machines.
Such a configuration might look like this:

```nix
vpn.networks.network1 = {
  backend = "wireguard";
  subnet = "10.0.0.0/24";
  server = {
    node = "host1";
    subnetIp = "10.0.0.1";
    wireguard.publicKey = "...";
    wireguard.privateKeyFile = "/...";
  };
  clients.host2 = {
    subnetIp = "10.0.0.2";
    wireguard.publicKey = "...";
    wireguard.privateKeyFile = "/...";
  };
  clients.host3 = {
    subnetIp = "10.0.0.3";
    wireguard.publicKey = "...";
    wireguard.privateKeyFile = "/...";
  };
}
```

This configures both the server and each client:
- The server will be configured to know the public keys of each client
- The clients will be configured to connect to the server and know its public key

For another example, see [my own configuration](https://github.com/infinisil/system/blob/4295f8e8646d8646406604c48e38be69b0759ced/config/multimods/vpn-setup.nix)

#### Other examples

Other examples include:
- An included by default [DNS record module](./modules/dns.nix) to allow assigning DNS entries
  without having to know which server controls the corresponding DNS zone.
  This could also be extended to easily support secondary DNS zones for redundancy.
- My personal [`rtcwake` module](https://github.com/infinisil/system/blob/4295f8e8646d8646406604c48e38be69b0759ced/config/multimods/rtcwake.nix),
  which allows suspending a machine but having it regularly wake up to check a server whether it should continue being suspending or not.
- My very rough and not self-contained personal [on-demand-minecraft module](https://github.com/infinisil/system/blob/4295f8e8646d8646406604c48e38be69b0759ced/config/multimods/on-demand-minecraft/default.nix),
  which runs [`on-demand-minecraft`](https://github.com/infinisil/on-demand-minecraft) on a machine,
  but also configures DNS SRV records on the DNS server.

Generally any NixOS module that interacts with other machines could benefit from being written in such a multi-module abstraction layer.

### Auto-rollback

Auto-rollback if the machine can't be reached via SSH anymore, protecting against a number of configuration mistakes such as
- Messing up the network config
- Removing your SSH key from the authorized keys
- The activation script failing in any way
- The boot activation failing in any way
- The system crashing during the deployment

#### Example

```
[foo.example.com] Connecting to host...
[foo.example.com] Copying closure to host...
[foo.example.com] copying 3 paths...
[foo.example.com] copying path '/nix/store/dh08694j23zbp6rra8wbhr9yy4vri49h-system-units' to 'ssh://root@138.68.83.114'...
[foo.example.com] copying path '/nix/store/xyslp1r2267vsrlrq73h79w31p2na223-etc' to 'ssh://root@138.68.83.114'...
[foo.example.com] copying path '/nix/store/3ndywy808vm6ahbwkmam4sqvxy0hv7hq-nixos-system-test-20.03pre-git' to 'ssh://root@138.68.83.114'...
[foo.example.com] Triggering system switcher...
[foo.example.com] Trying to confirm success...
[foo.example.com] Failed to activate new system! Rolled back to previous one
```

### Secret management

Tracks secrets through the Nix store,
automatically restarting services if they change,
but without including them in the Nix store.

## How to use it

Write a file like `example/default.nix`, then build the deployment script and call it
```
$ nix-build example/default.nix
these derivations will be built:
  /nix/store/lv8ck2k8b6vmsdp8wlqlpqr4shbkplfa-system-units.drv
  /nix/store/azyfd4qhv2hcdagcr8hmzwa2q284f9rh-etc.drv
  /nix/store/3kzhmi0flgcnpn6s5rym6hv8rs48hrs2-nixos-system-test-20.03pre-git.drv
  /nix/store/q6qx69mzy50llv3i7by5wwqyirqhpijy-deploy-foo.example.com.drv
  /nix/store/l7di8hzwa1m784ycqw01hdrybaxdi1jw-deploy.drv
building '/nix/store/lv8ck2k8b6vmsdp8wlqlpqr4shbkplfa-system-units.drv'...
building '/nix/store/azyfd4qhv2hcdagcr8hmzwa2q284f9rh-etc.drv'...
building '/nix/store/3kzhmi0flgcnpn6s5rym6hv8rs48hrs2-nixos-system-test-20.03pre-git.drv'...
building '/nix/store/q6qx69mzy50llv3i7by5wwqyirqhpijy-deploy-foo.example.com.drv'...
building '/nix/store/l7di8hzwa1m784ycqw01hdrybaxdi1jw-deploy.drv'...
/nix/store/z73pjq6d7n6f3xfhx9rycfk9sxqjmcav-deploy
$ ./result
[foo.example.com] Connecting to host...
[foo.example.com] Copying closure to host...
[foo.example.com] copying 3 paths...
[foo.example.com] copying path '/nix/store/f1028ijc3c2654z8ikzd378ryp644h3f-system-units' to 'ssh://root@138.68.83.114'...
[foo.example.com] copying path '/nix/store/9py44f4x9m83pr3j93c1fs95p0qy6175-etc' to 'ssh://root@138.68.83.114'...
[foo.example.com] copying path '/nix/store/8hbnksxrhgwpmia833xp8191a5yxw8ii-nixos-system-test-20.03pre-git' to 'ssh://root@138.68.83.114'...
[foo.example.com] Triggering system switcher...
[foo.example.com] Trying to confirm success...
[foo.example.com] Successfully activated new system!
```
