# Forgejo Actions self-hosted runner -- option declarations.
{lib, ...}: let
  types = lib.types;
in {
  options.nixfleet.ciRunner.forgejoActions = {
    enable = lib.mkEnableOption "Forgejo Actions self-hosted runner";

    instanceUrl = lib.mkOption {
      type = types.str;
      default = "http://localhost:3001";
      description = "URL of the Forgejo instance the runner registers with.";
    };

    registrationTokenFile = lib.mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/run/secrets/forgejo-runner-token";
      description = "Path to the runner registration token file. Required when forgejoActions.enable is true.";
    };

    name = lib.mkOption {
      type = types.str;
      default = "nixfleet-runner";
      description = "Runner display name.";
    };

    labels = lib.mkOption {
      type = types.listOf types.str;
      default = ["nixos:host" "native:host"];
      description = ''
        Labels the runner advertises to forgejo. The `:host` suffix
        is executor metadata -- forgejo strips it before label-matching,
        so workflow files use bare `runs-on: native` / `runs-on: nixos`.

        WORKFLOW AUTHORS: do NOT use `runs-on: ubuntu-latest` --
        no forgejo runner advertises that label and the job will
        silently never execute. See `LABELS.md` next to this file
        for the full contract.
      '';
    };

    capacity = lib.mkOption {
      type = types.int;
      default = 2;
      description = "Parallel jobs the runner accepts.";
    };

    enableContainers = lib.mkOption {
      type = types.bool;
      default = false;
      description = "Allow container-based jobs (needs docker/podman).";
    };
  };
}
