# Nginx web server - activates on agents tagged "web".
{
  config,
  lib,
  ...
}: let
  isWebAgent =
    config.services.nixfleet-agent.enable
    && builtins.elem "web" config.services.nixfleet-agent.tags;
in {
  services.nginx = lib.mkIf isWebAgent {
    enable = true;
    virtualHosts.default = {
      default = true;
      locations."/" = {
        return = "200 'nixfleet web server on ${config.networking.hostName}\n'";
        extraConfig = "default_type text/plain;";
      };
      locations."/health" = {
        return = "200 ok";
        extraConfig = "default_type text/plain;";
      };
    };
  };
}
