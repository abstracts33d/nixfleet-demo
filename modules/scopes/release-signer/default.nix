{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.nixfleet.releaseSigner;
  signWrapper = pkgs.writeShellApplication {
    name = "nixfleet-sign";
    runtimeInputs = [pkgs.openssh pkgs.coreutils];
    text = ''
      set -euo pipefail
      key="${cfg.stateDir}/key"
      [ -r "$key" ] || { echo "release-signer: $key missing" >&2; exit 1; }
      [ -n "''${NIXFLEET_INPUT:-}" ] || { echo "release-signer: NIXFLEET_INPUT unset" >&2; exit 1; }
      [ -n "''${NIXFLEET_OUTPUT:-}" ] || { echo "release-signer: NIXFLEET_OUTPUT unset" >&2; exit 1; }
      ssh-keygen -Y sign -f "$key" -n nixfleet-release < "$NIXFLEET_INPUT" > "$NIXFLEET_OUTPUT"
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
        key="${cfg.stateDir}/key"
        if [ ! -f "$key" ]; then
          ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -N "" -C "nixfleet-release" -f "$key"
          chmod 0640 "$key.pub"
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
