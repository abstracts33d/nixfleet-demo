# Trust pin for the demo fleet's release-signing key.
#
# This file is rewritten in place by `nix run .#fetch-release-key`
# after first boot: the script greps for the placeholder pubkey
# below and replaces it with the real ed25519 pubkey emitted by
# forge's first-boot keygen.
#
# Until the operator runs fetch-release-key, signature verification
# fails at runtime — but the flake still evaluates because this file
# is syntactically valid (the placeholder is valid base64 of 32 zero bytes).
{...}: {
  nixfleet.trust.ciReleaseKey.current = {
    algorithm = "ed25519";
    # 32 zero bytes, base64-encoded — placeholder. The real pubkey
    # lands here when the operator runs `nix run .#fetch-release-key`.
    public = "AAAAC3NzaC1lZDI1NTE5AAAAIGLqKj/0izdnwo+QhrwsVLx0z1VCnKgnWggPMg6FVJW9";
  };

  # Trust rotation slots are deliberately commented out for the demo.
  # In production the operator would populate `previous` during the
  # 30-day rotation grace window, then `successor` + `retireAt` to
  # pre-announce the next rotation. See nixfleet contracts/trust.nix.
  #
  # nixfleet.trust.ciReleaseKey.previous = { algorithm = "ed25519"; public = "..."; };
  # nixfleet.trust.ciReleaseKey.successor = { algorithm = "ed25519"; public = "..."; };
  # nixfleet.trust.ciReleaseKey.retireAt = "2027-01-01T00:00:00Z";
}
