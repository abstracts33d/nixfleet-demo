# Trust forge's demo cache.
#
# Imported by every agent host (cp, web-01, web-02). forge runs
# harmonia on :5000 (see modules/demo-cache.nix) which serves the
# closures CI built locally. Without this, agents can't realise the
# declared closure and rollouts stall at "don't know how to build".
#
# extra-substituters / extra-trusted-public-keys are additive: the
# upstream cache.nixos.org entry stays as the fallback for nixpkgs
# paths.
{...}: {
  nix.settings = {
    extra-substituters = ["http://forge:5000"];
    extra-trusted-public-keys = [
      (builtins.replaceStrings ["\n"] [""] (builtins.readFile ../secrets/cache-signing-key.pub))
    ];
  };
}
