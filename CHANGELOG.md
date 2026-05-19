# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/). Versioning: [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- `nix run github:arcanesys/nixfleet-demo` defaults to the single-host
  compliance bastion (NIS2-essential preset, signed evidence, no fleet).
- `nix run .#fleet` prints the 4-VM walkthrough hints in the terminal.
- macOS stubs for `apps.{aarch64,x86_64}-darwin.{default,fleet}` print a clean
  "needs Linux + KVM" message instead of failing cryptically.
- `services.harmonia` on forge serves `/nix/store` as the binary cache that
  agents fetch closures from (`modules/demo-cache.nix` +
  `modules/use-forge-cache.nix`).
- Operator surface on cp: `pkgs.git`, `programs.ssh.extraConfig` for `Host
  forge`, and `provision-secrets` stages `/var/lib/nixfleet-demo/demo-ssh-key`.
- Fleet-wide `modules/fleet-version.nix` imported by every fleet member so
  bumping the version string in one file cascades through all three closures.
- Signed bootstrap-nonce allowlist wired end-to-end (nixfleet#96): the
  regen script emits `secrets/bootstrap-nonces.nix`, `fleet.nix` declares
  it, CI passes `--bootstrap-nonces-attr`, `cp.nix` declares the
  `bootstrapNoncesSource`.
- `rolloutsSource` declared on cp so CP serves per-rollout manifests at
  `/v1/rollouts/<id>` without 503s.

### Changed
- Bumped `nixfleet` input to pick up the probe-failure rollback path:
  the reconciler now gates `Healthy → Soaked` on `all-probes-passing`
  (A, widened to surface `⚠ probes failing` in the status table for
  any non-Failed state), and a per-tick `sweep_soaked_health_failures`
  transitions `Soaked`/`Healthy` hosts with sustained
  `outstandingHealthFailures > 0` for >60s into `Failed`, re-entering
  the existing `rollback-and-halt` decision path (B). Demo step 10 now
  exercises the full path end-to-end.
- Three-channel topology (`edge`, `infra`, `stable`) chained by two
  `channelEdges`: `edge -> infra -> stable`. cp moves from `stable` to
  its own `infra` channel so the demo cascade walks the canonical
  real-world ordering (test ring -> control plane -> workloads). The
  README's step-9 cascade narration and the topology diagram reflect the
  new ordering. No new hosts or modules; pure fleet.nix rearrangement.
- Pinned nixfleet + nixfleet-compliance to `github:arcanesys/.../v0.2.0`.

### Known limitations
- Channel-level anti-thrash (refusing to re-dispatch the
  `quarantinedClosure` after a rollback) is deferred to v0.2.1, tracked
  in [arcanesys/nixfleet#99](https://github.com/arcanesys/nixfleet/issues/99).
  Until that lands, the operator must push a fix commit promptly after
  a rollback; otherwise the reconciler dispatches the same bad SHA on
  the next tick and the rollback loop repeats every ~60s.
- Bumped `compliance` input to pick up the `evidence-host-key` oneshot
  (so signing works on hosts without sshd) and the `nixfleet-compliance-verify`
  default paths (no-flags invocation works on the host that owns the evidence).
- Trimmed the bastion MOTD and `compliance-only/README.md` to the
  four-command loop: `compliance-check`, `nixfleet-compliance-verify`,
  tamper test, `systemctl start compliance-evidence-collector`.

### Fixed
- `hosts/cp.nix` now sets `services.nixfleet-control-plane.tls.clientCa`
  to `/etc/nixfleet-demo/fleet-ca.pem`. Without it, CP starts in TLS-only
  mode and rejects every `/v1/*` call with 401, breaking the operator
  CLI and the cp-self-agent reporting loop.
- `hosts/cp.nix` declares `environment.variables` for `NIXFLEET_CP_URL`,
  `NIXFLEET_CA_CERT`, `NIXFLEET_CLIENT_CERT`, `NIXFLEET_CLIENT_KEY` so
  `nixfleet status` on cp works without flags or `nixfleet config init`.
  The README already promised this; the wiring was missing.
- `forge` is no longer a fleet member - it runs the CI workflow, signs
  releases, and serves the binary cache. The chicken-and-egg of forge
  baking a trust pin matching the release key it regenerates on first
  boot is sidestepped by keeping CI hosts outside the fleet they ship to.
- Fleet shrinks from 4 visible hosts to 3 (`cp`, `web-01`, `web-02`).
- Canary wave `soakMinutes = 0` for a tight cascade in the demo recording
  (production fleets should restore 2-5 minutes).

### Removed
- `attic-server` scope and the dedicated `attic` flake input: harmonia
  replaced it. Drops ~390 lines of unused module code, an extra
  systemd oneshot, a port forward, and a persistence entry.
- v0.1 hosts: `db-01`, `mon-01`, `cache-01`.
- v0.1 modules under `modules/` (org-defaults, monitoring, web-server,
  vm-network, cache, tls). All replaced by lifted scopes or per-host config.

## [0.2.0] - 2026-05-15

### Changed
- **Complete rebuild as v0.2 minimal reference.** Topology shrunk from
  6 to 4 VMs (forge, cp, web-01, web-02). Single-screen `fleet.nix`
  exercises every v0.2 primitive (mkFleet schema, channels,
  rolloutPolicies, channelEdges, disruptionBudgets, complianceFrameworks,
  revocations).
- Pinned nixfleet and nixfleet-compliance to their `v0.2.0` tags.
- Demo CP declares `agentCnSuffix = "fleet.demo"` - required by nixfleet
  v0.2.0 (no default, refuses silent fallback).
- Adopted `hostSpec.vmRam` (4 GiB on forge, 2 GiB on cp). Removes the
  `--ram` flag boilerplate from the walkthrough.
- Dropped the `nixfleet-cp-artifact-bootstrap` consumer-side oneshot from
  `cp.nix` - framework now emits an equivalent one.
- Dropped the `boot.loader.systemd-boot.configurationLimit = 10`
  workaround from `_shared/qemu-vm.nix` - compliance #14 fix lets
  nullable values pass.
- Web hosts declare per-host HTTP health probes (nixfleet #86) on
  `/version` - reconciler gates Healthy -> Soaked promotion on
  probe-passing.
- `fleet.nix` carries a commented-out `tags.infra.pin` example
  (nixfleet #88) so operators see the commit-pin schema.
- Stable channel `compliance.mode = "permissive"` so the static gate runs
  every probe but warns rather than blocking - backup/MFA controls fail
  on this minimal demo, the warnings are the demonstration.
- Removed `nixfleet-scopes` flake input (retired upstream).
- Lifted forge / attic-server / ci-runner / coordinator scopes from the
  private `fleet` repo with org-specific identifiers stripped.
- New `release-signer` scope: file-based ed25519 signing replaces
  TPM-backed signing for demo simplicity.
- Three named flake apps: `start-vm`, `push-repo`, `fetch-release-key`.
- NIS2 essential compliance preset on cp.

### Removed
- v0.1 hosts: `db-01`, `mon-01`, `cache-01`.
- v0.1 modules under `modules/` (org-defaults, monitoring, web-server,
  vm-network, cache, tls). All replaced by lifted scopes or per-host
  config.
- Restic backup demonstration (out of scope for v0.2 minimal reference).

## [0.1.0] - 2026-04-19

Initial release. v0.1 history preserved at commit `2395f11` on the previous main.

[0.2.0-rc1]: https://github.com/arcanesys/nixfleet-demo/compare/2395f11...HEAD
[0.1.0]: https://github.com/arcanesys/nixfleet-demo/releases/tag/v0.1.0
