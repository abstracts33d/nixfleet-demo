# Demo binary cache on forge.
#
# harmonia serves forge's /nix/store over HTTP. CI compiles closures
# locally on forge during nixfleet-release; harmonia exposes them on
# port 5000 with no extra push step. Agents fetch via the substituter
# wired by modules/use-forge-cache.nix.
#
# Signing: the private cache-signing-key is staged into
# /var/lib/nixfleet-demo/ by `provision-secrets`. The matching pubkey
# is committed under secrets/ and baked into agent closures via
# nix.settings.extra-trusted-public-keys.
{...}: {
  services.harmonia.cache = {
    enable = true;
    settings.bind = "[::]:5000";
    signKeyPaths = ["/var/lib/nixfleet-demo/cache-signing-key"];
  };

  networking.firewall.allowedTCPPorts = [5000];

  # harmonia reads cache-signing-key on startup; gate the unit on it
  # so it stays inert (no crash-loop on missing-file) until
  # provision-secrets stages the file and starts it explicitly.
  systemd.services.harmonia.unitConfig.ConditionPathExists = "/var/lib/nixfleet-demo/cache-signing-key";
}
