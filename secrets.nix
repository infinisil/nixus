{ lib, pkgs, config, ... }:
let
  inherit (lib) types;
  # TODO (inspiration nixops):
  # - Add systemd units for each key
  # - persistent/non-persistent keys, send keys after reboot

  secretModule = { name, config, ... }: {
    options = {
      file = lib.mkOption {
        type = types.path;
        apply = value: pkgs.runCommandNoCC "secret-${name}" {
          # To find out which file to copy. toString to not import the secret into
          # the store
          file = toString value;

          # We make this derivation dependent on the secret itself, such that a
          # change of it causes a rebuild
          secretHash = builtins.hashString "sha512" (builtins.readFile value);
          # In Nix 2.3 this can be used:
          # secretHash = builtins.hashFile "sha512" value.file;
        } ''
          ln -s /run/keys/${name} $out
        '';
      };
    };
  };

in {

  options.secrets = lib.mkOption {
    type = types.attrsOf (types.submodule secretModule);
    default = {};
  };

  options.defaults = lib.mkOption {
    type = types.submodule {
      config.deployScripts.secrets = lib.dag.entryBefore ["switch"] ''
        dependencies() {
          nix-store -qR "$SYSTEM"
        }
        secrets() {
          echo "${lib.concatMapStringsSep "\n" (value: value.file) (lib.attrValues config.secrets)}"
        }

        includedSecrets=$(cat <(dependencies) <(secrets) | sort | uniq -d)

        echo "These secrets are included: $includedSecrets" >&2

        # TODO: Use tmpfs?
        ssh "$HOST" mkdir -p /run/keys

        loadedFiles=()

        for secret in $includedSecrets; do
          file=$(nix show-derivation "$secret" | jq '.[].env.file' -r)
          target=$(readlink "$secret")
          echo "Copying file $file to $target" >&2
          # TODO: Support secrets from commands, e.g. pass
          scp "$file" "$HOST":"$target"
          loadedFiles+=("$target")
        done

        echo "Finished copying secrets" >&2

      '';
      config.deployScripts.remove-secrets = lib.dag.entryAfter ["switch"] ''
        # TODO: Handle failing deploy
        echo "Unloading secrets that aren't needed" >&2
        while IFS= read -r -d "" secret; do
          echo "Is $secret still needed?" >&2
          for loaded in ''${loadedFiles[@]}; do
            if [ "$secret" == "$loaded" ]; then
              echo "Yes" >&2
              continue 2
            fi
          done
          echo "No" >&2
          ssh "$HOST" rm "$secret"
        done < <(ssh "$HOST" find /run/keys -type f -print0)
      '';
    };
  };

}
