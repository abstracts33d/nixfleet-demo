# Coordinator meta-scope — option declarations.
#
# Thin facade over the individual scopes (forge, attic-server, ci-runner,
# release-signer). Setting nixfleet.coordinator.enable = true cascades
# mkDefault enable flags to the sub-scopes; the consumer still configures
# each sub-scope through its own option path (nixfleet.forge.*,
# nixfleet.atticServer.*, ...).
{lib, ...}: {
  options.nixfleet.coordinator = {
    enable = lib.mkEnableOption ''
      This host is a fleet coordinator. Sets forge / attic-server /
      ci-runner / release-signer enable flags to lib.mkDefault true and
      acts as a discovery flag for scopes that want to adjust behaviour
      when running on a coordinator (for instance, the backup client
      scope skipping itself).
    '';

    domain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "example.org";
      description = "Base internal domain. Informational — individual scopes consume it to derive their own FQDNs.";
    };
  };
}
