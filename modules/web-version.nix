# Bump the version string below + `git push` to trigger the demo wave.
#
# Both web-01 and web-02 import this file. When the string changes, both
# host closures change. fleet.nix's channelEdges + canary policy gate the
# rollout: web-02 (edge, all-at-once) converges first, channelEdge releases
# stable, web-01 (canary, 2-min soak) converges next.
{...}: {
  services.nginx.virtualHosts.default.locations."/version".return = ''200 "1.0.0\n"'';
}
