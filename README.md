# nixfleet-demo

A 4-VM minimal reference implementation for [nixfleet](https://github.com/arcanesys/nixfleet) v0.2. Demonstrates the canonical GitOps loop end-to-end on your local machine: declarative fleet topology, signed release artifacts, channel-gated wave promotion, magic rollback. Read this file + `fleet.nix`, run three commands, and you have a working v0.2 fleet within ten minutes.

> **WARNING:** This repository ships with PUBLIC SSH and age keys under `secrets/demo-*` so newcomers can boot the fleet immediately. **These keys are public. Do not deploy this fleet to production.** See `secrets/README.md` to regenerate or rotate.

## Topology

| Host | Channel | Tag | Role |
|---|---|---|---|
| `forge` | `stable` | `infra` | Forgejo + attic-server + Forgejo Actions runner + ed25519 release-signer |
| `cp` | `stable` | `infra` | nixfleet control plane (polls forge for signed `fleet.resolved.json`) |
| `web-01` | `stable` | `web` | Agent, canary wave member |
| `web-02` | `edge` | `web` | Agent, all-at-once channel |

```
                    ┌─────────────┐
   git push ──────▶ │    forge    │ ◀── git push (CI signs fleet.resolved.json)
                    │  Forgejo    │
                    │  attic      │
                    │  CI runner  │
                    │  ed25519 sk │
                    └──────┬──────┘
                           │ HTTP (raw git URLs)
                           ▼
                    ┌─────────────┐       ┌──────────┐
                    │     cp      │ ────▶ │  web-01  │ (stable, canary)
                    │  nixfleet-  │       └──────────┘
                    │  control-   │       ┌──────────┐
                    │  plane      │ ────▶ │  web-02  │ (edge, all-at-once)
                    └─────────────┘       └──────────┘
```

## Network (host port forwards)

SSH ports are auto-assigned by `mkVmApps` (alphabetical, `2201 + index`). Additional service ports are declared per-host via `hostSpec.vmPortForwards` (nixfleet [#87](https://github.com/abstracts33d/nixfleet/issues/87)).

| Service | Guest port | Host port |
|---|---|---|
| cp SSH | 22 | 2201 |
| cp control plane | 8443 | 8443 |
| forge SSH (system) | 22 | 2202 |
| forge Forgejo SSH | 222 | 2222 |
| forge Forgejo HTTP | 3001 | 3001 |
| forge Attic | 8081 | 8081 |
| web-01 SSH | 22 | 2203 |
| web-01 nginx | 80 | 2280 |
| web-02 SSH | 22 | 2204 |
| web-02 nginx | 80 | 2281 |

## Prerequisites

- Nix with `flakes` and `nix-command` enabled
- QEMU/KVM (`/dev/kvm` accessible)
- ~6 GB free RAM
- ~20 GB free disk for VM state

## 9-step walkthrough

### 1. Generate the demo identity (first clone only)

```bash
bash secrets/regenerate-demo-identity.sh
```

Generates a fresh ed25519 SSH keypair at `secrets/demo-ssh-key{,.pub}` (mode 0600) and an age identity at `secrets/age-identity.txt`, then writes `secrets/recipients.nix`. The private keys are gitignored (OpenSSH refuses keys with mode > 0600, and git only tracks the +x bit, so we keep them out of git entirely). Both pubkey files (`demo-ssh-key.pub`, `recipients.nix`) are checked in for `nix flake check` to evaluate, and get rewritten by this script.

> **PUBLIC keys.** Even regenerated locally, these are demo identities. **Do not deploy this fleet to production.**

### 2. Build the VM disks (first time only)

```bash
nix run .#build-vm -- --all --identity-key secrets/demo-ssh-key
```

This boots a NixOS installer ISO under QEMU for each host, runs `nixos-anywhere` to install the host's config to a fresh `qcow2` disk under `~/.local/share/nixfleet/vms/`, and powers off. Subsequent `start-vm` invocations boot the installed disk directly. Re-run with `--rebuild` to wipe and reinstall.

Per-host VM memory is declared in `hosts/<name>.nix` via `hostSpec.vmRam` (`forge` runs at 4 GiB, `cp` at 2 GiB, web hosts at the 1 GiB default). Pass `--ram N` to override at runtime if needed.

Takes a few minutes per host on first run.

### 3. Boot forge and fetch its release-signing pubkey

```bash
nix run .#start-vm -- -h forge --vlan 1234
nix run .#fetch-release-key
```

The first command boots `forge` (which on first boot generates an ed25519 release-signing keypair under `/var/lib/nixfleet-release/`). The second polls forge:2202 for up to 60s, reads `/var/lib/nixfleet-release/key.pub` over SSH, copies the public key into `modules/trust.nix`, and commits the change locally.

Until this step completes, `cp` and the agents would bake a zero-pubkey placeholder into their trust JSON and reject every signed artifact at runtime.

### 4. Boot the rest of the fleet

```bash
nix run .#start-vm -- -h cp --vlan 1234
nix run .#start-vm -- -h web-01 --vlan 1234
nix run .#start-vm -- -h web-02 --vlan 1234
```

`cp`, `web-01`, `web-02` build with the real pubkey from step 3 baked into `/etc/nixfleet/agent/trust.json`. `forge` continues running (mkVmApps no-ops on already-running VMs). Each host's RAM comes from its `hostSpec.vmRam`.

`--vlan 1234` puts every VM on a shared QEMU multicast L2 so they can resolve each other by hostname (`cp`, `forge`, `web-01`, `web-02`). The static IP and `/etc/hosts` wiring is in `modules/vm-network.nix`. All four VMs must use the same VLAN port number.

### 5. Push the local repo into forge's Forgejo

```bash
nix run .#push-repo
```

Force-pushes the current branch to `git@localhost:2222/demo/fleet.git` (host port 2222 → guest port 222 via `vmPortForwards`). Forgejo Actions picks up the push, runs `.forgejo/workflows/ci.yml`, signs `releases/fleet.resolved.json` with the ed25519 key, commits the signature back to `main`. `cp` polls and verifies.

### 6. Watch convergence

```bash
ssh -p 2201 root@localhost          # SSH into cp
nixfleet status
nixfleet status --signed            # confirms signedAt + ciCommit on the artifact
```

All 4 hosts should report `Converged` within ~30s. If they don't, see Troubleshooting below.

### 7. Confirm the web tier

```bash
curl http://localhost:2280/version   # web-01 → 1.0.0
curl http://localhost:2281/version   # web-02 → 1.0.0
```

### 8. Trigger a wave promotion

Edit `modules/web-version.nix`: bump `1.0.0` to `1.0.1`. Then:

```bash
git add modules/web-version.nix
git commit -m "bump version"
nix run .#push-repo
```

Watch the rollout:

```bash
# inside cp:
nixfleet status --watch
```

Order:
1. `web-02` (edge, `all-at-once` policy) converges first.
2. `channelEdge` `{ gates = "edge"; gated = "stable"; }` releases.
3. `web-01` enters the canary wave for `stable`.
4. Soaks for 2 minutes (`soakMinutes = 2`).
5. Converges.

`curl http://localhost:2280/version` and `:2281/version` both return `1.0.1`.

### 9. Cause a rollback

Edit `hosts/web-01.nix` and inject an invalid nginx setting:

```nix
services.nginx.virtualHosts.default.listen = [ { addr = "999.999.999.999"; port = 80; } ];
```

Commit, push. `web-01`'s activation will fail. The reconciler enters `rollback-and-halt` per the canary policy's `onHealthFailure`. `nixfleet status` reports the rollout halted.

## What just happened — `fleet.nix` line by line

| Block | v0.2 primitive |
|---|---|
| `hosts.<name>.{system,configuration,tags,channel}` | mkFleet host registration with selector-friendly tags |
| `tags.<name>.description` | Tag declarations (referenced by selectors) |
| `channels.<name>.rolloutPolicy` | Per-channel policy reference |
| `channels.<name>.{reconcileIntervalMinutes,signingIntervalMinutes,freshnessWindow}` | Polling cadence + signed-artifact freshness window |
| `channels.<name>.compliance.mode` | Per-channel compliance enforcement (`enforce` / `permissive` / `disabled`) |
| `rolloutPolicies.canary.waves[].{selector,soakMinutes}` | Canary wave with a 2-min soak |
| `rolloutPolicies.canary.onHealthFailure` | `rollback-and-halt` triggers magic rollback |
| `channelEdges[].{gates,gated,reason}` | Cross-channel ordering: edge gates stable |
| `disruptionBudgets[].{selector,maxInFlight}` | At most one web host in flight |
| `complianceFrameworks` | Declared frameworks (NIS2 here) |
| `revocations = []` | Empty list — but the artifact still gets signed (gap-C path) |
| (commented in fleet.nix) `tags.<name>.pin = { commit, reason, expiresAt }` | Tag-scoped commit pin (#88) — freezes a tier on a known-good rev during audit windows |
| `services.nixfleet-agent.healthChecks.http = [{ url, expectStatus, ... }]` | Per-host HTTP/TCP/exec liveness probes (#86) — reconciler gates wave promotion on `all-probes-passing` |

## Cleanup

```bash
nix run .#stop-vm  -- --all
nix run .#clean-vm -- --all
```

Removes per-host VM state. Next `start-vm` re-runs first-boot oneshots (new ed25519 release key, new attic key, new runner token).

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `push-repo` says "forge Forgejo SSH not reachable on 2222" | forge not booted | `nix run .#start-vm -- -h forge` |
| `fetch-release-key` says "did not surface key.pub within 60s" | First-boot keygen still running | `ssh -p 2202 root@localhost journalctl -u nixfleet-release-keygen -f` |
| Agents log signature verification errors | trust.nix still has the zero-pubkey placeholder | Run `nix run .#fetch-release-key`, then `nix run .#clean-vm -- -h cp && nix run .#clean-vm -- -h web-01 && nix run .#clean-vm -- -h web-02 && nix run .#start-vm -- --all` |
| `nixfleet status` shows hosts as `Stale` | `freshnessWindow` exceeded; CI hasn't signed recently | Push again to retrigger CI |

## Regenerate demo identity after `git clone`

```bash
bash secrets/regenerate-demo-identity.sh --force
```

See `secrets/README.md`.

## References

- nixfleet — **temporarily** pinned to the abstracts33d fork on github (`github:abstracts33d/nixfleet`), `main` at `da54d0fffacc363f6003f223fd0ee8861ce6c07e`. Will swap to `github:arcanesys/nixfleet/<v0.2-tag>` once v0.2 ships canonically.
- nixfleet-compliance — **temporarily** pinned to the abstracts33d fork on github (`github:abstracts33d/nixfleet-compliance`), `main` at `176f6195e0ea3d03d10b3d750717d39f0888b814`. Provides `compliance.nixosModules.nis2`. Same future-swap as nixfleet.
- `docs/superpowers/specs/2026-05-07-v0.2-minimal-reference-design.md` — design spec for this rebuild
- `docs/superpowers/plans/2026-05-07-v0.2-minimal-reference-plan.md` — implementation plan
