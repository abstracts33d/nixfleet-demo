# Fleet topology -- RFC-0001 declarative declaration.
#
# Every block below teaches one v0.2 primitive. Read top-to-bottom:
#   - hosts: 4 VMs assigned to channels (web-01 stable, web-02 edge)
#   - tags: free-form labels for selectors
#   - channels: per-channel rolloutPolicy + intervals + freshness + compliance mode
#   - rolloutPolicies: canary with waves + soak + onHealthFailure
#   - channelEdges: cross-channel ordering (canonical gates/gated)
#   - disruptionBudgets: cap concurrent in-flight rollouts per selector
#   - complianceFrameworks: declared frameworks for this fleet
#   - revocations: empty list, but artifact still signed (gap C path)
{
  self,
  inputs,
  ...
}: {
  flake.fleet = inputs.nixfleet.lib.mkFleet {
    hosts = {
      forge = {
        system = "x86_64-linux";
        configuration = self.nixosConfigurations.forge;
        tags = ["infra"];
        channel = "stable";
      };
      cp = {
        system = "x86_64-linux";
        configuration = self.nixosConfigurations.cp;
        tags = ["infra"];
        channel = "stable";
      };
      web-01 = {
        system = "x86_64-linux";
        configuration = self.nixosConfigurations.web-01;
        tags = ["web"];
        channel = "stable";
        # Pre-shared SSH ed25519 pubkey from secrets/host-keys/web-01.pub.
        # The CP's /v1/enroll rejects any CSR whose pubkey doesn't match
        # this declaration -- pre-generation closes the chicken-and-egg
        # of "agent can't enroll because fleet.nix doesn't know its key
        # yet, fleet.nix can't declare the key because the agent hasn't
        # generated one yet." Run `bash secrets/regenerate-demo-identity.sh`
        # to (re)mint matching keys + tokens.
        pubkey = builtins.readFile ./secrets/host-keys/web-01.pub;
      };
      web-02 = {
        system = "x86_64-linux";
        configuration = self.nixosConfigurations.web-02;
        tags = ["web"];
        channel = "edge";
        pubkey = builtins.readFile ./secrets/host-keys/web-02.pub;
      };
    };

    tags = {
      web = {description = "Public web tier";};
      infra = {description = "Control-plane and forge";};
      # Per-tag commit pin (nixfleet #88). Uncomment to freeze every
      # `infra`-tagged host on a known-good commit during an audit
      # window -- `nixfleet-release` builds those hosts from the pinned
      # rev instead of the current commit, while everything else
      # follows main as usual. Pin precedence: host > tag > channel.
      #
      # infra = {
      #   description = "Control-plane and forge";
      #   pin = {
      #     commit = "<40-char-sha>";
      #     reason = "freeze infra tier for Q3 audit";
      #     expiresAt = "2026-12-31T00:00:00Z";
      #   };
      # };
    };

    channels = {
      stable = {
        rolloutPolicy = "canary";
        # Tight intervals for the demo (defaults: reconcile=30, signing=60).
        reconcileIntervalMinutes = 1;
        signingIntervalMinutes = 5;
        # Must be >= 2 * signingIntervalMinutes (RFC-0001 invariant).
        # Demo: 120 min tolerates an idle session between pushes (CI only
        # signs on push; a 15-min window forces the operator to keep
        # pushing just to keep the artifact fresh). Production: tighter
        # values + a scheduled re-sign workflow.
        freshnessWindow = 120;
        # Demo: permissive mode runs every probe and emits warnings
        # without blocking the build. Production fleets flip to "enforce"
        # once they have real backup units, MFA wiring, and a tracked
        # configurationRevision (and accept the build-time gate firing
        # whenever compliance regresses).
        compliance.mode = "permissive";
      };
      edge = {
        rolloutPolicy = "all-at-once";
        reconcileIntervalMinutes = 1;
        signingIntervalMinutes = 5;
        freshnessWindow = 120;
        # Edge tolerates compliance drift; stable enforces.
        compliance.mode = "permissive";
      };
    };

    rolloutPolicies = {
      canary = {
        strategy = "canary";
        waves = [
          {
            selector = {
              tags = ["web"];
              channel = "stable";
            };
            soakMinutes = 2;
          }
        ];
        onHealthFailure = "rollback-and-halt";
      };
      all-at-once = {strategy = "all-at-once";};
    };

    # Cross-channel ordering: edge must converge before stable promotes.
    channelEdges = [
      {
        gates = "edge";
        gated = "stable";
        reason = "Edge must converge before stable promotes.";
      }
    ];

    # At most one web host in flight at a time.
    disruptionBudgets = [
      {
        selector = {tags = ["web"];};
        maxInFlight = 1;
      }
    ];

    complianceFrameworks = ["nis2"];

    # Empty -- but the signed artifact still gets produced. CP rebuilt
    # from empty state can verify the (empty) revocation set (gap C).
    revocations = [];
  };
}
