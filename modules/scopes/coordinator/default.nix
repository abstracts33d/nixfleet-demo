# Coordinator meta-scope. Imports the full coordinator bundle and
# defaults their enable flags on when nixfleet.coordinator.enable is
# set. Individual sub-scope configuration stays at the sub-scope's own
# option path -- this module does not pass options through.
{
  config,
  lib,
  ...
}: let
  cfg = config.nixfleet.coordinator;
in {
  imports = [
    ./options.nix
    ../forge/forgejo
    ../cache-server/attic-server
    ../ci-runner/forgejo-actions
    ../release-signer
  ];

  config = lib.mkIf cfg.enable {
    nixfleet.forge.enable = lib.mkDefault true;
    nixfleet.atticServer.enable = lib.mkDefault true;
    nixfleet.ciRunner.forgejoActions.enable = lib.mkDefault true;
    nixfleet.releaseSigner.enable = lib.mkDefault true;
  };
}
