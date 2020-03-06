Features I thought of putting in a deployment tool:
- Separate concepts of deployment node and network node. A host can either be a deployment node, a network node, none or both, with state transitions:
  - At the start all hosts are neither deployment nor network node
  - To get started, you make a host a deployment node by installing the deployment tool on it (or cloning the repository of the network)
  - Configuring another host to deploy to in the network config file makes it a network node
  - Configuring to deploy to localhost makes the local host both a deployment node and a network node
  - A deployment node that's also a network node should always be able to do changes to itself, even when all other nodes are offline
  - Track which deployment network a node belongs to, to prevent conflicts. Or perhaps a node could be in multiple networks?
- Automatic decentralized version tracking with git remotes and/or branches.
  - All network nodes have a copy of the network git repo with their latest changes
  - So if we deploy to a remote network node, we first `git pull` from that host to know of any changes it did to itself, and merge those into our own changes with git
  - As a result we could get a git graph of a branch for every network node with merges between them
  - This allows both Alice and Bob to do changes to host C independently, without any changes being lost or Alice and Bob coordinating
  - TODO: How does this interact with the next point?
- Ability to write multi-host abstraction modules
  - E.g. to configure a VPN network with this node as a server and these ones as clients, abstracted away in a single module
  - Allows users to write such modules themselves
- Authorization for deployments based on own SSH keys
  - If you have root SSH access to a remote machine with your own SSH key, you are allowed to do deployments to it
  - Same for root access to the local machine
  - To allow other people to do changes to machines, deploy an update to the machine that adds their ssh keys (or set up an SSH CA to give a group of people access at once)
  - Ideally have a NixOS module that easily allows doing this (TODO: What about ssh key generation?)
- Allow different nixpkgs versions for different network nodes

Some other features I'd like to have, but not thought out as well:
- Ability for it to install NixOS on non-NixOS hosts with already the correct initial configuration, creating a new network node, fully automatically hopefully
- Non-persistent (and persistent?) secret management
- Health checks
- Automatically take care of running nixos-generate-config, so it doesn't have to be called manually which could be forgotten

- Copy the Nix from the target host to localhost and use that to communicate to the daemon, such that there's no version mismatch
