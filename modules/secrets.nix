{ lib, pkgs, config, options, ... }:
let
  inherit (lib) types;
  # Ideas (inspiration nixops):
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

  # Intersects the closure of a system with a set of secrets
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

in {

  options.defaults = lib.mkOption {
    type = types.submodule ({ config, ... }: {
      options.configuration = lib.mkOption {
        type = types.submodule {
          options.secrets = lib.mkOption {
            type = types.attrsOf (types.submodule secretType);
            default = {};
          };
        };
      };

      config =
        let
          includedSecrets = requiredSecrets {
            system = config.configuration.system.build.toplevel;
            secrets = config.configuration.secrets;
          };
        in {

        deployScripts.secrets = lib.dag.entryBefore ["switch"] ''
          echo "Copying secrets..." >&2

          ssh "$HOST" mkdir -p ${keyDirectory}

          while read -r json; do
            name=$(echo "$json" | jq -r '.name')
            source=$(echo "$json" | jq -r '.source')
            echo "Copying secret '$name'" >&2
            scp "$source" "$HOST":${keyDirectory}/"$name"
          done < ${includedSecrets}
        '';

        deployScripts.remove-secrets = lib.dag.entryAfter ["switch"] ''
          if [ "$status" = success ]; then
            mapfile -t requiredNames < <(jq -r '.name' ${includedSecrets})

            echo "Removing secrets that aren't needed anymore..." >&2
            while IFS= read -r -d "" secret; do
              for name in "''${requiredNames[@]}"; do
                if [ "${keyDirectory}/$name" = "$secret" ]; then
                  continue 2
                fi
              done
              echo "Removing secret '$secret'"
              ssh "$HOST" rm "$secret"
            done < <(ssh "$HOST" find ${keyDirectory} -type f -print0)
          fi
        '';
      };
    });
  };

}
