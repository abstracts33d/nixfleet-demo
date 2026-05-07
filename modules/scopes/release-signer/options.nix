{lib, ...}: {
  options.nixfleet.releaseSigner = {
    enable = lib.mkEnableOption "ed25519 release-signing keyslot for nixfleet-release";
    user = lib.mkOption {
      type = lib.types.str;
      default = "gitea-runner";
      description = ''
        Service user that owns the private key and runs `nixfleet-sign`.
        Must match the user under which the CI runner executes the
        nixfleet-release binary. Defaults to the static user provisioned
        by the ci-runner/forgejo-actions scope (`gitea-runner`).
      '';
    };
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/nixfleet-release";
      description = "Directory holding the ed25519 key and key.pub.";
    };
  };
}
