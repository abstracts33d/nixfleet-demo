# Binary cache client - configures agent hosts to pull from cache-01.
{
  config,
  lib,
  ...
}: let
  agentHosts = ["web-01" "web-02" "db-01" "mon-01"];
  hostName = config.networking.hostName;
  isAgent = builtins.elem hostName agentHosts;
in {
  services.nixfleet-cache = lib.mkIf isAgent {
    enable = true;
    cacheUrl = "http://cache-01:5000";
    publicKey = builtins.readFile ../secrets/cache-signing-key.pub;
  };
}
