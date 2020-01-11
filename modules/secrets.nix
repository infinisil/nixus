{ lib, pkgs, config, options, ... }:
let
  inherit (lib) types;
  # TODO (inspiration nixops):
  # - Add systemd units for each key
  # - persistent/non-persistent keys, send keys after reboot

  # Abstract where the secret is gotten from (different hosts, not only localhost, different commands, not just files)

  keyDirectory = "/run/keys";

  secretType = { name, ... }: {
    options = {
      file = lib.mkOption {
        type = types.path;
        apply = indirectSecret name;
      };
      target = lib.mkOption {
        type = types.path;
        apply = toString;
        default = keyDirectory + "/" + name;
      };
    };
  };

  # Takes a file path and turns it into a derivation
  indirectSecret = name: file: pkgs.runCommandNoCC "secret-${name}" {
    # To find out which file to copy. toString to not import the secret into
    # the store
    file = toString file;

    # We make this derivation dependent on the secret itself, such that a
    # change of it causes a rebuild
    secretHash = builtins.hashString "sha512" (builtins.readFile file);
    # TODO: Switch to `builtins.hashFile "sha512" value`
    # which requires Nix 2.3. The readFile way can cause an error when it
    # contains null bytes
  } ''
    ln -s ${keyDirectory}/${name} $out
  '';

  # Derivation that has two outputs
  # serialize: A script that:
  # - Collects secrets on localhost
  # - Checks all their hashes
  # - Generates a single stream
  #
  # unserialize: A script that:
  # - Reads and decodes the stream from send
  # - Checks all the hashes
  # - Installs secrets at the appropriate places
  #
  # In the end, $recv should be transferred to the target host
  # Then something like this should be called to install the secrets:
  # $ send | ssh "$HOST" recv
  requiredSecrets = { system, secrets }: pkgs.stdenv.mkDerivation {
    name = "required-secrets";

    __structuredAttrs = true;
    preferLocalBuild = true;

    exportReferencesGraph.system = system;
    secrets = lib.mapAttrsToList (name: value: {
      inherit name;
      path = value.file;
      source = value.file.file;
      hash = value.file.secretHash;
      target = value.target;
    }) secrets;

    PATH = lib.makeBinPath [pkgs.buildPackages.jq];

    builder =
      let
        jqFilter = builtins.toFile "jq-filter" ''
          [.system[].path] as $system
          | .secrets[]
          | select(.path == $system[])
        '';
      in builtins.toFile "builder" ''
        source .attrs.sh
        jq -r -c -f ${jqFilter} .attrs.json > ''${outputs[out]}
      '';
  };


  # Takes a requiredSecrets file as input and outputs an archive of all secrets collected
  # TODO: Incremental packing: Get secret list from target host and only send the secrets it doesn't have already
  packer = pkgs.writeScript "secret-packer" ''
    #!${pkgs.runtimeShell}
    PATH=${pkgs.lib.makeBinPath [ pkgs.coreutils pkgs.gnutar pkgs.jq ]}
    echo "Packing up all necessary secrets.." >&2
    set -e
    tmp=$(mktemp -d)
    trap "rm -r $tmp" exit

    cp /dev/stdin "$tmp/meta"
    mkdir "$tmp/files"

    while read -r json; do
      name=$(echo "$json" | jq -r '.name')
      source=$(echo "$json" | jq -r '.source')
      hash=$(echo "$json" | jq -r '.hash')
      cp "$source" "$tmp/files/$name"
      if [ ! "$(sha512sum "$tmp/files/$name" | cut -d' ' -f1)" == "$hash" ]; then
        echo "Secret at path $source doesn't have the expected hash" >&2
        echo "Either restore the file to the previous state or rebuild the deployment" >&2
        exit 1
      fi
    done < "$tmp/meta"

    tar -C "$tmp" -cf - .
  '';

  unpacker = pkgs.writeScript "secret-unpacker" ''
    #!${pkgs.runtimeShell}
    PATH=${pkgs.lib.makeBinPath [ pkgs.coreutils pkgs.gnutar pkgs.jq ]}
    set -e
    tmp=$(mktemp -d)
    trap "rm -r $tmp" exit

    echo "Unpacking secrets on destination.." >&2

    tar -C "$tmp" -xf -

    while read -r json; do
      name=$(echo "$json" | jq -r '.name')
      target=$(echo "$json" | jq -r '.target')
      mkdir -p "$(dirname "$target")"
      cp "$tmp/files/$name" "$target"
    done < "$tmp/meta"
  '';


in {

  options.globalSecrets = lib.mkOption {
    type = types.attrsOf (types.submodule secretType);
    default = {};
  };

  options.defaults = lib.mkOption {
    type = types.submodule ({ config, ... }: {
      options = {
        secrets = lib.mkOption {
          type = types.attrsOf (types.submodule secretType);
          default = {};
        };

        requiredSecrets = lib.mkOption {
          type = types.package;
          internal = true;
          readOnly = true;
          description = ''
            A derivation containing information on all secrets that are required
            by this node.
          '';
        };
      };

      config = {

        # The global secrets are available by default too
        secrets = lib.zipAttrsWith (name: values:
          lib.mkDefault (lib.mkMerge values)
        ) options.globalSecrets.definitions;

        # This needs to be on the target machine so secrets can be unpacked
        closurePaths = [ unpacker ];

        requiredSecrets = requiredSecrets {
          system = config.configuration.system.build.toplevel;
          secrets = config.secrets;
        };

        deployScripts.secrets = lib.dag.entryBefore ["switch"] ''

          echo "Deploying secrets.." >&2

          # TODO: Implement secret loading at runtime
          ssh "$HOST" 'if [ ! -d /run/keys ]; then
            mkdir -p /run/keys
            mount -t ramfs -o size=1M ramfs /run/keys;
          fi'

          set -e
          ${packer} < ${config.requiredSecrets} | ssh "$HOST" ${unpacker}
          set +e

          echo "Finished deploying secrets" >&2
        '';

        #deployScripts.remove-secrets = lib.dag.entryAfter ["switch"] ''
        #  # TODO: Handle failing deploy
        #  echo "Unloading secrets that aren't needed" >&2
        #  while IFS= read -r -d "" secret; do
        #    echo "Is $secret still needed?" >&2
        #    for loaded in ''${loadedFiles[@]}; do
        #      if [ "$secret" == "$loaded" ]; then
        #        echo "Yes" >&2
        #        continue 2
        #      fi
        #    done
        #    echo "No" >&2
        #    ssh "$HOST" rm "$secret"
        #  done < <(ssh "$HOST" find /run/keys -type f -print0)
        #'';
      };
    });
  };

}
