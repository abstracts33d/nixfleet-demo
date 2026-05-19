# Fleet-wide version string imported by every host (forge, cp,
# web-01, web-02). Bumping this string shifts every host's closure
# at once, which is what the signed-chain GIF wants to demonstrate:
# one operator-side edit cascading through all four hosts via the
# signed-GitOps loop.
#
# Setting it as a NIX option (not just an environment.variables entry)
# would couple it to a service. We want the simplest possible "every
# closure depends on this value" surface, so we use
# environment.etc -- a literal string on disk, no service wiring,
# changing the string forces a new system generation.
{...}: {
  environment.etc."nixfleet-demo/fleet-version".text = "1.0.0\n";
}
