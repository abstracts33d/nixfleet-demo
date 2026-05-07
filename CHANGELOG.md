# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/). Versioning: [Semantic Versioning](https://semver.org/).

## [0.2.0-rc1] - Unreleased

### Changed
- **Complete rebuild as v0.2 minimal reference.** Topology shrunk from 6 to 4 VMs
  (forge, cp, web-01, web-02). Single-screen `fleet.nix` exercises every v0.2
  primitive (mkFleet schema, channels, rolloutPolicies, channelEdges,
  disruptionBudgets, complianceFrameworks, revocations).
- Pinned nixfleet (and nixfleet-compliance) to the abstracts33d fork on github
  until v0.2 ships canonically on `arcanesys`. Pin: `ef7ab4e3` for nixfleet
  (covers #86 health probes, #87 vmPortForwards, #88 commit pins, #89 wait_ssh fix,
  #90 CP self-bootstrap, #92 hostSpec.vmRam), `abff3d8e` for nixfleet-compliance
  (#14 null configurationLimit). Will swap to `github:arcanesys/...` later.
- Adopted `hostSpec.vmRam` (4 GiB on forge, 2 GiB on cp). Removes the
  `--ram` flag boilerplate from the walkthrough.
- Dropped the `nixfleet-cp-artifact-bootstrap` consumer-side oneshot from
  `cp.nix` — framework now emits an equivalent one.
- Dropped the `boot.loader.systemd-boot.configurationLimit = 10` workaround
  from `_shared/qemu-vm.nix` — compliance #14 fix lets nullable values pass.
- Web hosts declare per-host HTTP health probes (nixfleet #86) on `/version` —
  reconciler gates Healthy → Soaked promotion on probe-passing.
- `fleet.nix` carries a commented-out `tags.infra.pin` example (nixfleet #88)
  so operators see the commit-pin schema.
- Stable channel `compliance.mode = "permissive"` so the static gate runs
  every probe but warns rather than blocking — backup/MFA controls fail on
  this minimal demo, the warnings are the demonstration.
- Removed `nixfleet-scopes` flake input (retired upstream).
- Lifted forge / attic-server / ci-runner / coordinator scopes from the private
  `fleet` repo with org-specific identifiers stripped.
- New `release-signer` scope: file-based ed25519 signing replaces TPM-backed signing
  for demo simplicity.
- Three named flake apps: `start-vm`, `push-repo`, `fetch-release-key`.
- NIS2 essential compliance preset on cp.

### Removed
- v0.1 hosts: `db-01`, `mon-01`, `cache-01`.
- v0.1 modules under `modules/` (org-defaults, monitoring, web-server, vm-network,
  cache, tls). All replaced by lifted scopes or per-host config.
- Restic backup demonstration (out of scope for v0.2 minimal reference).

## [0.1.0] - 2026-04-19

Initial release. v0.1 history preserved at commit `2395f11` on the previous main.

[0.2.0-rc1]: https://github.com/arcanesys/nixfleet-demo/compare/2395f11...HEAD
[0.1.0]: https://github.com/arcanesys/nixfleet-demo/releases/tag/v0.1.0
