# Trust pin for the demo fleet's release-signing key.
#
# This file is rewritten in place by `nix run .#fetch-release-key`
# after first boot: the script greps for the placeholder pubkey
# below and replaces it with the real ed25519 pubkey emitted by
# forge's first-boot keygen.
#
# Until the operator runs fetch-release-key, signature verification
# fails at runtime - but the flake still evaluates because this file
# is syntactically valid (the placeholder is valid base64 of 32 zero bytes).
{...}: {
  nixfleet.trust.ciReleaseKey.current = {
    algorithm = "ed25519";
    public = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  # orgRootKey.current is a bare-string slot (algorithm pinned to
  # ed25519 framework-side; see nixfleet's keySlotType in
  # contracts/trust.nix). Patched by
  # secrets/regenerate-demo-identity.sh from secrets/org-root.pub.b64.
  nixfleet.trust.orgRootKey.current = "Zfx1CHKqaTtbMIJOVdXthyIiJcttoNnN3cmcqnqyV/Q=";

  # Trust rotation slots are deliberately commented out for the demo.
  # In production the operator would populate `previous` during the
  # 30-day rotation grace window, then `successor` + `retireAt` to
  # pre-announce the next rotation. See nixfleet contracts/trust.nix.
  #
  # nixfleet.trust.ciReleaseKey.previous = { algorithm = "ed25519"; public = "A1RMnXqG6ZTJLXtEApN0EkbOV373a/VaU/H/RgqzGYk="; };
  # nixfleet.trust.ciReleaseKey.successor = { algorithm = "ed25519"; public = "A1RMnXqG6ZTJLXtEApN0EkbOV373a/VaU/H/RgqzGYk="; };
  # nixfleet.trust.ciReleaseKey.retireAt = "2027-01-01T00:00:00Z";
}
