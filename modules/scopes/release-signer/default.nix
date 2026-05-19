{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.nixfleet.releaseSigner;
  # nixfleet-release's --sign-cmd hook receives canonical bytes via
  # NIXFLEET_INPUT and must write the raw 64-byte ed25519 signature
  # to NIXFLEET_OUTPUT. The trust contract pairs this with a raw
  # 32-byte ed25519 pubkey (base64-encoded) in trust.json.
  #
  # Implementation: openssl pkeyutl -sign -rawin -inkey <PEM-ed25519>.
  # Earlier versions used `ssh-keygen -Y sign` which produces SSHSIG
  # armored format - incompatible with nixfleet's verify_artifact.
  signWrapper = pkgs.writeShellApplication {
    name = "nixfleet-sign";
    runtimeInputs = [pkgs.openssl pkgs.coreutils];
    text = ''
      set -euo pipefail
      key="${cfg.stateDir}/key.pem"
      [ -r "$key" ] || {
        echo "release-signer: $key missing" >&2
        exit 1
      }
      [ -n "''${NIXFLEET_INPUT:-}" ] || {
        echo "release-signer: NIXFLEET_INPUT unset" >&2
        exit 1
      }
      [ -n "''${NIXFLEET_OUTPUT:-}" ] || {
        echo "release-signer: NIXFLEET_OUTPUT unset" >&2
        exit 1
      }
      openssl pkeyutl -sign -rawin -inkey "$key" -in "$NIXFLEET_INPUT" -out "$NIXFLEET_OUTPUT"
    '';
  };
in {
  imports = [./options.nix];

  config = lib.mkIf cfg.enable {
    users.groups.nixfleet-release = {};

    systemd.tmpfiles.rules = [
      "d ${cfg.stateDir} 0750 ${cfg.user} nixfleet-release - -"
    ];

    systemd.services.nixfleet-release-keygen = {
      description = "First-boot ed25519 keygen for nixfleet release signing";
      wantedBy = ["multi-user.target"];
      after = ["local-fs.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = cfg.user;
        Group = "nixfleet-release";
        UMask = "0027";
      };
      script = ''
        set -euo pipefail
        key="${cfg.stateDir}/key.pem"
        pub="${cfg.stateDir}/key.pub.b64"
        if [ ! -f "$key" ]; then
          # Generate raw ed25519 keypair in PEM format. openssl writes
          # PKCS#8 PrivateKey for the secret half.
          ${pkgs.openssl}/bin/openssl genpkey -algorithm ed25519 -out "$key"
          chmod 0600 "$key"
        fi
        if [ ! -f "$pub" ]; then
          # Extract the raw 32-byte ed25519 pubkey, base64-encoded.
          # `openssl pkey -in $key -pubout -outform DER` emits a 44-byte
          # SubjectPublicKeyInfo: 12-byte ASN.1 wrapper + 32-byte raw key.
          # Strip the wrapper (skip first 12 bytes) and base64.
          ${pkgs.openssl}/bin/openssl pkey -in "$key" -pubout -outform DER \
            | tail -c 32 \
            | ${pkgs.coreutils}/bin/base64 -w 0 > "$pub"
          chmod 0644 "$pub"
        fi
      '';
    };

    # systemPackages places the wrapper at /run/current-system/sw/bin/nixfleet-sign,
    # which is on the default PATH for any service. CI workflow invokes it
    # by bare name `nixfleet-sign`.
    environment.systemPackages = [signWrapper];

    nixfleet.persistence.directories = [
      {
        directory = cfg.stateDir;
        user = cfg.user;
        group = "nixfleet-release";
        mode = "0750";
      }
    ];
  };
}
