# Fleet topology - RFC-0001 declarative declaration.
#
# Every block below teaches one v0.2 primitive. Read top-to-bottom:
#   - hosts: 3 fleet members (cp on stable, web-01 stable, web-02 edge).
#     forge is intentionally NOT a fleet member -- it's the CI/cache/trust
#     anchor, outside the fleet it ships to (see the host block below).
#   - tags: free-form labels for selectors; tag-scoped healthChecks live here
#   - channels: per-channel rolloutPolicy + intervals + freshness
#     (compliance is per-probe now -- see healthChecks block; RFC-0010 §3.4)
#   - healthChecks: fleet-wide probe set; per-probe `mode` replaces v0.1's
#     channel-level compliance.mode (RFC-0010)
#   - rolloutPolicies: canary with waves + soak + onHealthFailure
#   - channelEdges: cross-channel ordering (canonical gates/gated)
#   - disruptionBudgets: cap concurrent in-flight rollouts per selector
#   - revocations: empty list, but artifact still signed (gap C path)
#   - bootstrapNonces: signed allowlist of valid bootstrap-token nonces
#     (nixfleet#96); imported from secrets/bootstrap-nonces.nix which
#     is regenerated alongside the tokens by regenerate-demo-identity.sh
{inputs, ...}: {
  flake.fleet = inputs.nixfleet.lib.mkFleet {
    hosts = {
      # forge is INTENTIONALLY not a fleet member. It runs the CI workflow,
      # signs releases, and serves the binary cache (harmonia) -- it is the
      # trust anchor for everything else. Including forge as an agent target
      # creates a chicken-and-egg: forge regenerates its release key on
      # first boot, but its own closure bakes a trust pin from build time,
      # so forge can never verify rollout manifests signed by its own key.
      # Cleaner architecture: forge is outside the fleet, like build farms
      # in real-world deployments.
      cp = {
        system = "x86_64-linux";
        # Per-host mkHost args (RFC-0011 §2.2 + 9e operator path). The
        # framework's mkFleet wrapper iterates `hosts` and calls mkHost
        # with `hostName`, `platform`, and `fleetResolved` pre-bound;
        # `nixosArgs` carries the rest (modules / hostSpec / isVm).
        # Built configs surface at `self.fleet.nixosConfigurations.cp`.
        nixosArgs = import ./hosts/cp.nix {inherit inputs;};
        tags = ["infra"];
        # cp runs on its own `infra` channel so the demo's channel/edge
        # cascade is two hops, not one: edge (web-02) -> infra (cp) ->
        # stable (web-01). With cp on `stable` the chain collapses to
        # a single edge and the canonical real-world pattern (push the
        # control plane upgrade before promoting workloads that depend
        # on it) doesn't surface.
        channel = "infra";
        # cp runs its own agent reporting to itself over loopback. Brief
        # /v1/* outage on cp self-rollout is acceptable -- agents on web
        # hosts retry with backoff and CP comes back up within a poll.
        pubkey = builtins.readFile ./secrets/host-keys/cp.pub;
      };
      web-01 = {
        system = "x86_64-linux";
        nixosArgs = import ./hosts/web-01.nix {inherit inputs;};
        tags = ["web"];
        channel = "stable";
        # Pre-shared SSH ed25519 pubkey from secrets/host-keys/web-01.pub.
        # The CP's /v1/enroll rejects any CSR whose pubkey doesn't match
        # this declaration - pre-generation closes the chicken-and-egg
        # of "agent can't enroll because fleet.nix doesn't know its key
        # yet, fleet.nix can't declare the key because the agent hasn't
        # generated one yet." Run `bash secrets/regenerate-demo-identity.sh`
        # to (re)mint matching keys + tokens.
        pubkey = builtins.readFile ./secrets/host-keys/web-01.pub;
      };
      web-02 = {
        system = "x86_64-linux";
        nixosArgs = import ./hosts/web-02.nix {inherit inputs;};
        tags = ["web"];
        channel = "edge";
        pubkey = builtins.readFile ./secrets/host-keys/web-02.pub;
      };
    };

    tags = {
      web = {
        description = "Public web tier";
        # Tag-scoped probe (RFC-0010 §3.2): every host with the `web`
        # tag runs nginx-version. One declaration covers web-01 +
        # web-02; previously this lived per-host in
        # hosts/web-{01,02}.nix's `services.nixfleet-agent.healthChecks`.
        # `mode = "enforce"` means the wave-promotion gate refuses to
        # advance past a host whose latest result is Fail.
        healthChecks = {
          nginx-version = {
            kind = "http";
            url = "http://localhost/version";
            expectStatus = 200;
            intervalSeconds = 15;
            mode = "enforce";
          };
        };
      };
      infra = {description = "Control plane";};
      # Per-tag commit pin (nixfleet #88). Uncomment to freeze every
      # `infra`-tagged host on a known-good commit during an audit
      # window - `nixfleet-release` builds those hosts from the pinned
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

    # Fleet-wide health probes (RFC-0010 §3.1). Every host in the fleet
    # picks these up unless overridden at tag or host scope. The v0.2.1
    # equivalent of v0.1's channel-level `compliance.mode = "permissive"`
    # is `mode = "observe"` here -- the probe runs and its results land
    # in event_log, but the wave-promotion gate ignores them. Flip to
    # `mode = "enforce"` in production once you trust the compliance
    # signal enough to gate on it.
    healthChecks = {
      evidence-nis2 = {
        kind = "evidence";
        framework = "nis2";
        intervalSeconds = 60;
        mode = "observe";
      };
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
      };
      edge = {
        rolloutPolicy = "all-at-once";
        reconcileIntervalMinutes = 1;
        signingIntervalMinutes = 5;
        freshnessWindow = 120;
      };
      # `infra` carries the control-plane closure. all-at-once because
      # there is only one infra host and a canary wave of size one is
      # pointless. Sequenced in the channelEdges chain so the demo
      # cascade visibly traverses three channels: edge -> infra -> stable.
      infra = {
        rolloutPolicy = "all-at-once";
        reconcileIntervalMinutes = 1;
        signingIntervalMinutes = 5;
        freshnessWindow = 120;
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
            # 0 = skip soak window. Demo recording wants a tight cascade
            # (~30s per host) rather than a realistic 2-minute hold. The
            # `Converged` state is still gated on health probes; only the
            # additional soak timer is removed. Production fleets keep
            # this at 2-5 minutes.
            soakMinutes = 0;
          }
        ];
        onHealthFailure = "rollback-and-halt";
      };
      all-at-once = {strategy = "all-at-once";};
    };

    # Cross-channel ordering: edge gates infra, infra gates stable.
    # Two chained edges so the demo cascade walks the full chain:
    #   edge (web-02) -> infra (cp) -> stable (web-01)
    # When a release only touches the web closures (the README's step 9
    # bump), `infra`'s wave is a no-op (cp's hash unchanged) but the
    # reconciler still walks through it and unblocks `stable` in the
    # same tick. That visibly demonstrates that a no-op channel still
    # participates in the ordering contract.
    channelEdges = [
      {
        gates = "edge";
        gated = "infra";
        reason = "Edge must converge before infra promotes.";
      }
      {
        gates = "infra";
        gated = "stable";
        reason = "Infra must converge before stable workloads promote.";
      }
    ];

    # At most one web host in flight at a time. cp (the only infra host)
    # also caps at one, redundant with the cardinality but explicit.
    disruptionBudgets = [
      {
        selector = {tags = ["web"];};
        maxInFlight = 1;
      }
      {
        selector = {tags = ["infra"];};
        maxInFlight = 1;
      }
    ];

    # Empty - but the signed artifact still gets produced. CP rebuilt
    # from empty state can verify the (empty) revocation set (gap C).
    revocations = [];

    # Signed allowlist of bootstrap-token nonces (nixfleet#96). CP refuses
    # /v1/enroll for any nonce not in this list. The file is regenerated
    # by regenerate-demo-identity.sh from each token's claims and tracked
    # in git so the flake evaluates on a fresh clone.
    bootstrapNonces = import ./secrets/bootstrap-nonces.nix;
  };
}
