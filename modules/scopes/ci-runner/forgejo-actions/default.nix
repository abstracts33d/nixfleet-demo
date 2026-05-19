# Forgejo Actions self-hosted runner driver.
#
# One of two CI-runner siblings under the `nixfleet.ciRunner.*`
# umbrella; coexists with the `hercules` driver (different
# subnamespace, different services). Both can run on the same
# host if the operator imports both scopes.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.nixfleet.ciRunner.forgejoActions;
in {
  imports = [./options.nix];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.registrationTokenFile != null;
        message = "nixfleet.ciRunner.forgejoActions.enable requires forgejoActions.registrationTokenFile.";
      }
    ];

    services.gitea-actions-runner = {
      package = pkgs.forgejo-runner;
      instances.nixfleet = {
        enable = true;
        inherit (cfg) name;
        url = cfg.instanceUrl;
        tokenFile = cfg.registrationTokenFile;
        labels = cfg.labels;
        settings = {
          runner.capacity = cfg.capacity;
          container.enable = cfg.enableContainers;
          log.level = "info";
        };
      };
    };

    # Runner environment - two things:
    #
    # 1. Give the runner (and its subprocess shells) access to Nix
    #    and the standard toolchain every `runs-on: native`
    #    workflow expects. Without this, jobs fail with "command
    #    not found".
    #
    #    Uses NixOS's `.path` attribute - additive, merges the
    #    listed packages into PATH without touching the rest of the
    #    env. (The earlier `serviceConfig.Environment = ["PATH=..."]`
    #    approach REPLACED the entire env - stripped HOME,
    #    LOCALE_ARCHIVE, TZDIR etc. and broke the runner at
    #    activation.)
    #
    #    Consumers that need extras (a TPM-sign
    #    wrapper, etc.) extend this list from their own host config:
    #
    #        systemd.services.gitea-runner-nixfleet.path = [ inputs.attic... ];
    #
    # 2. Order the runner after forgejo.service when the runner
    #    points at a local Forgejo instance. Avoids a race on
    #    rebuild where both services restart simultaneously, runner
    #    boots before forgejo accepts connections, and exits 1.
    #    systemd auto-retries and succeeds ~2s later, but the
    #    visible exit status on nixos-rebuild looks like a failure.
    systemd.services.gitea-runner-nixfleet =
      {
        path = with pkgs; [
          config.nix.package
          bash
          coreutils
          findutils
          gnugrep
          gnused
          gawk
          gnutar
          gzip
          git
          jq
          curl
          openssl
        ];
        # Static system user instead of upstream's DynamicUser=true.
        # DynamicUser implies an idmapped StateDirectory bind mount
        # that systemd hardens with `noexec` - fatal for `runs-on:
        # native` workflows that compile + execute artifacts (cargo
        # build scripts, test binaries) under the runner's working
        # dir. Static user -> plain bind mount, exec-clean, and the
        # state dir lands on the persisted btrfs subvol with room
        # to grow.
        #
        # PrivateTmp also disabled: the upstream module sets it to
        # `yes` (and DynamicUser=true would force it on regardless),
        # which gives the service a 1.6 GB tmpfs for /tmp. Too small
        # for the release pipeline - `attic push` buffers multi-GB
        # nar files in /tmp, then `nixfleet-release` writes the
        # canonical-bytes tempfile, and the cumulative footprint
        # hits ENOSPC. Falling back to the host /tmp (root fs, 300+
        # GB free here) trades a small isolation property for build
        # success - acceptable for a runner that already needs broad
        # system access for nix + attic + tpm-sign.
        #
        # NB: a brief detour through DynamicUser=true + mkForce
        # PrivateTmp=false was tried; systemd ignores the explicit
        # PrivateTmp override when DynamicUser=true is on (implicit
        # always wins), so PrivateTmp came back as yes and /tmp
        # capped at 1.5 GB again. Keep static-user.
        serviceConfig = {
          DynamicUser = lib.mkForce false;
          User = lib.mkForce "gitea-runner";
          Group = lib.mkForce "gitea-runner";
          PrivateTmp = lib.mkForce false;
        };
      }
      // lib.optionalAttrs (lib.hasPrefix "http://localhost" cfg.instanceUrl
        || lib.hasPrefix "http://127.0.0.1" cfg.instanceUrl) {
        after = ["forgejo.service"];
        wants = ["forgejo.service"];
      };

    # Regime-transition guard. Past activations have left
    # /var/lib/gitea-runner in the wrong shape after toggling
    # DynamicUser=true ↔ false:
    #
    #   - DynamicUser=true makes /var/lib/gitea-runner a symlink to
    #     /var/lib/private/gitea-runner (created at unit start).
    #   - DynamicUser=false expects a regular directory owned by
    #     the static gitea-runner user.
    #
    # If the previous generation was DynamicUser=true and this one
    # is static, systemd's StateDirectory= setup fails with "File
    # exists" / status=238/STATE_DIRECTORY and the unit gets stuck
    # in restart loop. Strip the stale symlink before activation;
    # systemd creates the regular dir on first start.
    #
    # Idempotent: regular directories are left alone.
    system.activationScripts.nixfleet-gitea-runner-statedir = ''
      if [ -L /var/lib/gitea-runner ]; then
        rm /var/lib/gitea-runner
      fi
    '';

    users.users.gitea-runner = {
      isSystemUser = true;
      group = "gitea-runner";
      home = "/var/lib/gitea-runner";
    };
    users.groups.gitea-runner = {};

    nixfleet.persistence.directories = ["/var/lib/gitea-runner"];
  };
}
