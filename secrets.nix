{ lib, pkgs, config, ... }:
let
  inherit (lib) types;
  # TODO (inspiration nixops):
  # - Add systemd units for each key
  # - persistent/non-persistent keys, send keys after reboot

  # Abstract where the secret is gotten from (different hosts, not only localhost, different commands, not just files)

  secrets = config.secrets;

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
          # TODO: Switch to `builtins.hashFile "sha512" value`
          # which requires Nix 2.3. The readFile way can cause an error when it
          # contains null bytes
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
    type = types.submodule ({ config, ... }: {
      config.deployScripts.secrets =
        let
          # Derivation that has two outputs
          # send: A script that:
          # - Collects secrets on localhost
          # - Checks all their hashes
          # - Generates a single stream
          #
          # recv: A script that:
          # - Reads and decodes the stream from send
          # - Checks all the hashes
          # - Installs secrets at the appropriate places
          #
          # In the end, $recv should be transferred to the target host
          # Then something like this should be called to install the secrets:
          # $send | ssh "$HOST" recv
          secretTransfer = null;

          closureThing = pkgs.stdenv.mkDerivation {
            name = "secrets-to-deploy";
            __structuredAttrs = true;

            exportReferencesGraph.system = config.configuration.system.build.toplevel;

            secrets = lib.mapAttrsToList (name: value: {
              inherit name;
              storeFile = value.file;
              sourceFile = value.file.file;
              hash = value.file.secretHash;
            }) secrets;

            preferLocalBuild = true;

            PATH = "${pkgs.buildPackages.coreutils}/bin:${pkgs.buildPackages.jq}/bin";

            builder = builtins.toFile "builder" ''
              . .attrs.sh
              out=''${outputs[out]}
              mkdir -p $out
              # Finds paths that are both in .secrets and .system
              jq -r '[.system[].path] as $system | .secrets | map(select( .storeFile as $value | $system | bsearch($value) >= 0))' .attrs.json > $out/secretsToDeploy
              cp .attrs.json $out/attrs
            '';
          };

        in lib.dag.entryBefore ["switch"] ''
        dependencies() {
          nix-store -qR "$SYSTEM"
        }
        secrets() {
          nix-store -qR "${builtins.trace closureThing.outPath closureThing}"
        }

        includedSecrets=$(cat <(dependencies) <(secrets) | sort | uniq -d)

        echo "These secrets are included: $includedSecrets" >&2

        # TODO: Use tmpfs? ramfs is better
        ssh "$HOST" mkdir -p /run/keys

        loadedFiles=()



        for secret in $includedSecrets; do
          read -r file hash <<< \
            $( nix show-derivation /nix/store/xcsc9lx5wrv8ncp6avwdg7ypl3rabbwv-secret-foo \
            | jq '.[].env | "\(.file) \(.secretHash)"' -r)

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
    });
  };

}
