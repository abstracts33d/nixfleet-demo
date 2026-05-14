# Trust pins for the demo fleet.
#
# Two trust slots: ciReleaseKey (verifies signed fleet.resolved.json
# from forge's CI runner) and orgRootKey (verifies bootstrap tokens
# at /v1/enroll). Both keys are ed25519 raw 32-byte pubkeys, base64-
# encoded -- the trust.json wire format.
#
# `ciReleaseKey.current` is patched in place by `nix run .#fetch-release-key`
# after forge's first boot; `orgRootKey.current` is patched by
# `bash secrets/regenerate-demo-identity.sh` from secrets/org-root.pub.b64.
# Until both have real values, runtime verification fails -- but the
# flake still evaluates because the placeholders are valid base64.
{...}: {
  nixfleet.trust.ciReleaseKey.current = {
    algorithm = "ed25519";
    public = "TVViJeqEv1P6ZLiku0JgLeHOqXVYtaTYE9rNO3NDyHA=";
  };

  # orgRootKey.current is a bare-string slot (algorithm pinned to
  # ed25519 framework-side; see nixfleet's keySlotType in
  # contracts/trust.nix). Patched by
  # secrets/regenerate-demo-identity.sh from secrets/org-root.pub.b64.
  nixfleet.trust.orgRootKey.current = "YTBSsRFbp9hAXqyXp4XFBhqcaSxKU7VRhl3HtRHDfQ0=";

  # Trust rotation slots are deliberately commented out for the demo.
  # In production the operator would populate `previous` during the
  # 30-day rotation grace window, then `successor` + `retireAt` to
  # pre-announce the next rotation. See nixfleet contracts/trust.nix.
  #
  # nixfleet.trust.ciReleaseKey.previous = { algorithm = "ed25519"; public = "TVViJeqEv1P6ZLiku0JgLeHOqXVYtaTYE9rNO3NDyHA="; };
  # nixfleet.trust.ciReleaseKey.successor = { algorithm = "ed25519"; public = "TVViJeqEv1P6ZLiku0JgLeHOqXVYtaTYE9rNO3NDyHA="; };
  # nixfleet.trust.ciReleaseKey.retireAt = "2027-01-01T00:00:00Z";
}
