# nixfleet-demo

[![CI](https://github.com/arcanesys/nixfleet-demo/actions/workflows/ci.yml/badge.svg)](https://github.com/arcanesys/nixfleet-demo/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE-MIT)

Local reference fleet for [NixFleet](https://github.com/arcanesys/nixfleet) v0.2 and [NixFleet Compliance](https://github.com/arcanesys/nixfleet-compliance) v0.2. Two paths in one repo:

- **Quick demo (single host, default `nix run`).** One NixOS VM, NIS2-essential preset, signed evidence on disk in 2-5 minutes. No fleet, no control plane.
- **Reference fleet (QEMU VMs).** Three fleet members (`cp` control plane, `web-01`, `web-02`) plus `forge` (CI + binary cache + release signer; intentionally outside the fleet). Exercises the canonical signed-GitOps loop end to end: declarative fleet topology, signed release artifacts, channel-gated wave promotion, magic rollback. First run is 45-90 minutes on a cold nixpkgs cache; subsequent rollouts converge in 1-3 minutes.

## Quick demo

```bash
nix run github:arcanesys/nixfleet-demo
# (VM boots, auto-login at the serial console)
compliance-check                  # signed evidence + control table
nixfleet-compliance-verify        # auditor tool, defaults to /var/lib/nixfleet-compliance/
echo '{"host":"attacker"}' > /var/lib/nixfleet-compliance/evidence.json
nixfleet-compliance-verify        # tamper test: exit 2, "signature verification failed"
systemctl start compliance-evidence-collector   # restore real signed evidence
```

One NixOS VM with the NIS2-essential compliance preset. No fleet, no control plane, no orchestration. Exit with `Ctrl-A x` (twice).

Requires Nix with flakes enabled and `/dev/kvm` accessible. macOS users: see [docs/macos.md](docs/macos.md). The same demo lives standalone under [`compliance-only/`](compliance-only/) if you want to evaluate the subflake in isolation.

## Full reference fleet (one-shot)

Three fleet members (`cp` control plane, `web-01`, `web-02`) plus `forge` (CI runner + Forgejo + binary cache + release signer; outside the fleet it serves). Declarative fleet topology, signed release artifacts, channel-gated wave promotion, magic rollback. First run takes 45-90 min on a cold nixpkgs cache while forge compiles the nixfleet Rust workspace from source. Subsequent rollouts complete in 1-3 min.

```bash
git clone https://github.com/arcanesys/nixfleet-demo && cd nixfleet-demo
nix run .#fleet-up        # full setup (identity + 4 VMs + first push) ~30-45 min cold
# (wait for CI to sign the first manifest; see hints printed at the end)
nix run .#fleet-promote   # step 9: wave promotion via web-version bump
nix run .#fleet-rollback  # step 10: probe-gated rollback + halt
nix run .#fleet-recover   # revert the rollback test commit
nix run .#fleet-down      # stop + clean every VM
```

`fleet-up` handles every gotcha that the manual walkthrough below stumbles over: ssh-agent isolation, build-vm teardown of the installer ISO, adaptive polling for cold-boot keygen, every internal SSH bypassing the operator's agent. Watch CI progress at <http://localhost:3001/demo/fleet/actions> (Forgejo Actions web UI) — easiest signal that the first signed manifest has landed.

> **WARNING:** This repository ships with PUBLIC SSH and age keys under `secrets/demo-*` so newcomers can boot the fleet immediately. **These keys are public. Do not deploy this fleet to production.** See `secrets/README.md` to regenerate or rotate.

## Topology

| Host | Fleet member | Channel | Tag | Role |
|---|---|---|---|---|
| `forge` | no | n/a | n/a | Forgejo + harmonia binary cache + Forgejo Actions runner + ed25519 release-signer |
| `cp` | yes | `infra` | `infra` | nixfleet control plane (polls forge); runs an agent reporting to itself over loopback |
| `web-01` | yes | `stable` | `web` | Agent, canary wave member |
| `web-02` | yes | `edge` | `web` | Agent, all-at-once channel |

`forge` is intentionally NOT a fleet member — a host that both signs and verifies its own rollouts hits a chicken-and-egg on first-boot key regeneration. Three channels (`edge → infra → stable`) chained by two `channelEdges` mirror the real-world test-ring → control-plane → workloads promotion pattern. Step 9's cascade walks all three.

## Network (host port forwards)

SSH ports are auto-assigned by `mkVmApps` (alphabetical, `2201 + index`). Additional service ports are declared per-host via `hostSpec.vmPortForwards` (nixfleet [#87](https://github.com/arcanesys/nixfleet/issues/87)).

| Service | Guest port | Host port |
|---|---|---|
| cp SSH | 22 | 2201 |
| cp control plane | 8443 | 8443 |
| forge SSH (system) | 22 | 2202 |
| forge Forgejo SSH | 222 | 2222 |
| forge Forgejo HTTP | 3001 | 3001 |
| forge harmonia (binary cache) | 5000 | 5000 |
| web-01 SSH | 22 | 2203 |
| web-01 nginx | 80 | 2280 |
| web-02 SSH | 22 | 2204 |
| web-02 nginx | 80 | 2281 |

## Prerequisites

- Nix with `flakes` and `nix-command` enabled
- QEMU/KVM (`/dev/kvm` accessible)
- ~6 GB free RAM
- ~20 GB free disk for VM state

`fleet-up` handles the rest (ssh-agent isolation, forge disk sizing, installer-ISO tuning, per-step ordering). Operational footguns from earlier sessions live in Troubleshooting.

## 10-step walkthrough (manual reference)

`nix run .#fleet-up` runs steps 1-6 in order. The breakdown below is the per-phase reference — useful when you want to inspect a specific phase or redo just one step. First-pass readers can skip to [What this demo proves](#what-this-demo-proves).

### 1. Generate the demo identity (first clone only)

```bash
bash secrets/regenerate-demo-identity.sh
```

Mints the SSH key, fleet CA, operator cert, per-host mTLS keys, org root keypair, and signed bootstrap-nonce allowlist. See [`secrets/README.md`](secrets/README.md) for the file matrix. Bootstrap tokens expire after 168h.

### 2. Build the VM disks

```bash
nix run .#build-vm -- --all --identity-key secrets/demo-ssh-key
```

`nixos-anywhere` installs each host into a fresh qcow2 under `~/.local/share/nixfleet/vms/`. A few minutes per host.

### 3. Boot forge + fetch its release-signing pubkey

```bash
nix run .#start-vm -- -h forge --vlan 1234
nix run .#fetch-release-key
```

forge generates an ed25519 release-signing keypair on first boot. `fetch-release-key` reads the pubkey over SSH and commits it into `modules/trust.nix`. Skip and every CI signature gets rejected as `BadSignature` downstream.

### 4. Boot the rest

```bash
nix run .#start-vm -- -h cp     --vlan 1234
nix run .#start-vm -- -h web-01 --vlan 1234
nix run .#start-vm -- -h web-02 --vlan 1234
```

`--vlan 1234` puts every VM on a shared multicast L2. Agents and CP stay inert (gated on operator-private material the next step lands).

### 5. Provision operator-private material

```bash
nix run .#provision-secrets -- --all
```

scps the per-host private keys into `/var/lib/nixfleet-demo/` and starts the gated services. Private keys never enter the flake source.

### 6. Push the local repo into forge's Forgejo

```bash
nix run .#push-repo
```

Force-pushes to `git@localhost:2222/demo/fleet.git`. Forgejo Actions signs `releases/fleet.resolved.json`, commits the signature back. **First push: 20-45 min** (cold Rust workspace + 4 closures). Subsequent: 2-5 min. Track via web UI at <http://localhost:3001/demo/fleet/actions>.

### 7. Watch convergence

```bash
ssh -p 2201 root@localhost
nixfleet status
```

The operator CLI picks up `NIXFLEET_CP_URL` + cert paths from cp's `environment.variables`. `503 Service Unavailable` until CI signs the first sidecar (lifts within ~30s).

All 3 fleet members report `Converged` within ~30s of CP turning ready. Order per `channelEdges`: `web-02` (edge) → `cp` (infra) → `web-01` (stable canary).

### 8. Confirm the web tier

```bash
curl http://localhost:2280/version   # web-01 -> 1.0.0
curl http://localhost:2281/version   # web-02 -> 1.0.0
```

### 9. Trigger a wave promotion

Shortcut: `nix run .#fleet-promote` (auto-bumps the patch component of `modules/web-version.nix`, commits, pushes). The manual equivalent — edit `modules/web-version.nix`, bump `1.0.0` to `1.0.1`, then:

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
2. `channelEdge` `{ gates = "edge"; gated = "infra"; }` releases.
3. `cp` (infra, `all-at-once`) — its closure is unchanged by this bump, so the channel completes instantly. The reconciler still walks through it; that's the contract.
4. `channelEdge` `{ gates = "infra"; gated = "stable"; }` releases.
5. `web-01` enters the canary wave for `stable`.
6. Soak elapses (`soakMinutes = 0` in the demo for a tight cascade; production fleets use 2-5 minutes).
7. Converges.

`curl http://localhost:2280/version` and `:2281/version` both return `1.0.1`.

### 10. Cause a rollback

Shortcut: `nix run .#fleet-rollback` (injects + commits + pushes); recover with `nix run .#fleet-recover`. Manual equivalent — edit `hosts/web-01.nix` and inject an invalid nginx listen address:

```nix
services.nginx.virtualHosts.default.listen = [{addr = "999.999.999.999"; port = 80;}];
```

Commit, push:

```bash
git add hosts/web-01.nix
git commit -m "demo: bad listen"
nix run .#push-repo
```

The closure activates fine (symlink switch succeeds — `listen=999.999.999.999` is syntactically valid Nix), but nginx fails to start at the systemd level (`emerg: host not found in '999.999.999.999:80'`). The agent's `/version` probe immediately starts returning connection-refused.

Watch the state machine work in `nixfleet status` (or `nixfleet rollout events <id>` for the full signed event log; `nixfleet rollout hosts <id>` for the per-host snapshot):

1. **`→ activating`.** Agent switches the systemd symlink. `listen=999.999.999.999` is syntactically valid Nix, so activation itself succeeds.
2. **`→ soaking → ⚠ probes failing`.** Soak window opens. The agent's `/version` probe returns connection-refused (nginx-pre-start dies on `999.999.999.999`); CLI surfaces `⚠ probes failing` during the soak.
3. **`✗ failed`.** Sustained-failure detection runs **on the agent** (not CP — see nixfleet RFC-0008 §4.2). After the threshold elapses the agent emits a signed `Failed` event. No CP-side sweep, no race.
4. **`✗ reverted — channel halted, push fix`.** The agent reads the rollout manifest's `onHealthFailure = "rollback-and-halt"` directly — a single signed source of truth — and autonomously reverts to the previous closure. No CP `RollbackSignal` (removed in v0.2). CP records the bad SHA in `quarantinedClosure`; `/v1/deferrals` lists it; the `stable` channel parks on the previous-good SHA until the operator publishes a different one.

```bash
curl http://localhost:2280/version    # 1.0.0 again — the bad rollout never reached end-users
```

Recovery is push-driven: revert the bad commit (or push a fix). The new SHA differs from `quarantinedClosure`, the halt lifts, the channel resumes normal promotion.

If the recovery happens to land on a closure the host *already rolled back to* (Nix store paths are content-addressed — reverting source produces the prior SHA), convergence is instant: `current == declared`, no re-dispatch, no re-soak. Forward-fix to a known-good state is a no-op.

## What this demo proves

The push you just made traversed five primitives that turn "ssh into a host and edit configs by hand" into auditor-grade signed-GitOps:

1. **Signed-GitOps loop.** Every artifact (`fleet.resolved.json`, `revocations.json`, `bootstrap-nonces.json`, per-rollout manifests) is ed25519-signed by forge. CP rejects unsigned or wrong-key payloads as `BadSignature`. Every operator/agent/CP call is mTLS — unauthenticated requests return 401.
2. **Channel + wave promotion (step 9).** Three channels chained by two `channelEdges`: `edge → infra → stable`. A bad commit cannot skip from edge to production without crossing the chain. Predecessor channels gate successors.
3. **Magic rollback + halt (step 10).** Bad nginx config → `→ soaking → ⚠ probes failing → ✗ failed → ✗ reverted — channel halted, push fix`. The agent (not CP) detects sustained probe failure and autonomously reverts; CP quarantines the bad SHA and halts further dispatches. Blast radius: one canary host for ~2-3 min (120s sustained-failure threshold + activation + rollback fire). No end-user traffic affected.
4. **Signed compliance evidence (step 7 + bastion).** Host signs `evidence.json` with its SSH ed25519 key. `nixfleet-compliance-verify` reproduces the auditor recipe offline. Tamper the file → exit 2 with cryptographic failure. No operator trust, no scanner vendor.
5. **Zero-trust bootstrap.** Org-root-signed bootstrap-nonce allowlist gates `/v1/enroll` (CP refuses unknown nonces). Per-host mTLS certs issued by the fleet CA at first checkin.

**v0.2 architectural guarantees that make the loop above auditable.**

- **Event-driven state machine.** Every transition has an explicit ed25519-signed event written to CP's `event_log`. State is never inferred from checkin diffs. Replay any rollout's chronological timeline with `nixfleet rollout events <id>` (engineer surface) or pull the per-host snapshot with `nixfleet rollout hosts <id>` (operator surface).
- **Pure-functional reducer + applier split.** Agents and CP both run the same `step(state, event) → state'` function, so transition semantics cannot drift between the two sides.
- **Agent-decided rollback.** The agent reads `onHealthFailure` from the signed rollout manifest directly. CP never queues a `RollbackSignal` — one signed source of truth for the policy.
- **Event log as audit trail.** Blocked dispatches are recorded as `kind='gate_decision'` rows with reason; `/v1/deferrals` surfaces them for operators.
- **Disk-backed outbound queue on the agent.** Events survive agent restart mid-rollout (one fsync per event).
- **Multi-scope health probes with per-probe `mode`.** Declarations layer at fleet → tag → host scope (RFC-0010); `mode` (`enforce | observe | disabled`) is per-probe, so compliance/HTTP/exec probes share one axis instead of channel-level special cases. Enforce-mode failures land in the `probe_failures` derived view, written by the applier in the same transaction as the `event_log` row (FK-back to canonical; lose the view → walk the log to rebuild it).
- **Rollout-level state machine + uniform derived-view discipline.** Rollouts have their own 8-state reducer in `nixfleet-state-machine` (RFC-0012): `Opening → Active → Converging → Terminal`, with `Reverted`/`Failed`/`Superseded`/`Pruned` exits. Transitions are signed `kind='rollout_event'` rows in `event_log`; `rollouts` + `quarantined_closures` are now derived views with `event_log_seq` FK-back to canonical, written in the same transaction as the triggering event. `/v1/rollouts/<id>/events` surfaces per-host + rollout-level events chronologically.

**The auditor's view.** Hand them the git history + the signed `releases/` sidecars + the host pubkeys. They can reconstruct exactly what was deployed where and when, verify cryptographically, see live compliance posture, and observe that bad commits self-revert before reaching end users — without trusting the operator.

### What this demo deliberately doesn't push (production would)

- Evidence probe declared at fleet scope with `mode = "observe"` (the v0.2.1 replacement for v0.1's channel-level `compliance.mode = "permissive"`) → flip to `mode = "enforce"` so the wave-promotion gate refuses to advance past hosts whose compliance evidence is failing.
- `soakMinutes = 0` for tight cascade timing → production canary waves run 2-5 min.
- Single host per channel → `disruptionBudgets[].maxInFlight = 1` is trivially satisfied; real fleets exercise the cap.
- Tag-scoped commit pins (audit-window freezes) — present in `fleet.nix` as a commented example.

## Cleanup

```bash
nix run .#fleet-down            # stops + cleans every VM in one go
```

Equivalent manual steps:

```bash
nix run .#stop-vm  -- --all
nix run .#clean-vm -- --all
```

Removes the qcow2 disks. To rebuild, just rerun `nix run .#fleet-up` — it handles the forge-first + key-fetch + rest-of-fleet ordering automatically.

Manual equivalent (if you want to drive each step yourself): **forge must be rebuilt + booted + key-fetched BEFORE the rest** so cp/web-NN bake the rotated trust pin:

```bash
nix run .#build-vm -- -h forge --rebuild --identity-key secrets/demo-ssh-key
nix run .#start-vm -- -h forge --vlan 1234
nix run .#fetch-release-key                       # rotates trust.nix to forge's new key

for h in cp web-01 web-02; do
  nix run .#build-vm -- -h $h --rebuild --identity-key secrets/demo-ssh-key
  nix run .#start-vm -- -h $h --vlan 1234
done
nix run .#provision-secrets -- --all
nix run .#push-repo
```

> ⚠️ **Order matters** (the reason `fleet-up` exists). Building cp/web-NN before `fetch-release-key` bakes the old (or placeholder) pin and CP rejects every CI signature as `BadSignature`. Only fix: rebuild downstream a second time (~20 min waste). `fetch-release-key` is idempotent — safe to re-run anytime.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `push-repo` says "forge Forgejo SSH not reachable on 2222" | forge not booted, or disks were wiped by `clean-vm` and need `build-vm` again | `nix run .#build-vm -- -h forge --identity-key secrets/demo-ssh-key && nix run .#start-vm -- -h forge --vlan 1234` |
| `start-vm` says `[<host>] No disk found. Run build-vm first.` | `clean-vm` removed the qcow2; need to reinstall before booting | `nix run .#build-vm -- -h <host> --identity-key secrets/demo-ssh-key` |
| `fetch-release-key` says "did not surface key.pub within 60s" | First-boot keygen still running | `ssh -p 2202 root@localhost journalctl -u nixfleet-release-keygen -f` |
| CP log says `BadSignature` on revocations or fleet.resolved.json polls (`verify_revocations` / `verify_artifact`) | `forge` was wiped by a later `clean-vm`, regenerated its release keypair, but `cp`/`web-NN` closures still bake the OLD trust pin | Re-rotate + rebuild downstream: `nix run .#fetch-release-key && for h in cp web-01 web-02; do nix run .#clean-vm -- -h $h && nix run .#build-vm -- -h $h --rebuild --identity-key secrets/demo-ssh-key && nix run .#start-vm -- -h $h --vlan 1234; done && nix run .#provision-secrets -- --all && nix run .#push-repo`. This is the **#1 trap** in the demo - see "Cleanup" section for the correct ordering. |
| Agents log signature verification errors AND `trust.nix` has `wKiZ+...AAA=` (zero-pubkey placeholder) | First-time bootstrap never reached `fetch-release-key` | Run `nix run .#fetch-release-key`, then clean+rebuild cp + agent hosts as above |
| Agents log `enroll: 401` or `bootstrap-token expired` | Bootstrap token >168h old, or `modules/trust.nix` orgRootKey mismatch | `bash secrets/regenerate-demo-identity.sh --force`, then clean+rebuild affected web hosts |
| Agents log `enroll: 400 declared pubkey mismatch` | `secrets/host-keys/web-NN.pub` was regenerated but `fleet.nix`'s readFile cached, OR `/etc/ssh/ssh_host_ed25519_key` wasn't refreshed | Rebuild the host (`nix run .#build-vm -- -h web-NN --rebuild ...`) |
| `nixfleet status` shows hosts as `Stale` | `freshnessWindow` (120 min for this demo) exceeded; CI hasn't signed recently | Push again to retrigger CI |
| `nixfleet status` returns `503 Service Unavailable` | First CI run hasn't yet produced + signed `releases/fleet.resolved.json`; CP gates `/v1/*` on the readiness flags (nixfleet#95) | Wait for CI to finish - cold first run is 20-45 min |
| CI step fails with `error: writing to file: No space left on device` | Forge accumulates `/nix/store` paths from each CI run. Default qcow2 is 5G; after 3-4 cold-cycle runs it fills up | Either: clean-wipe forge (`stop-vm` + `clean-vm` + `build-vm -- -h forge --rebuild --disk-size 15G ...`) OR run `ssh -p 2202 root@localhost nix-collect-garbage -d` to GC older generations. The first push that re-warms after GC will take longer because some store paths must be rebuilt. |
| CI run logs `task N repo is demo/fleet` then nothing more; status flips to `failed` with no error in `journalctl -u gitea-runner-nixfleet` | Same disk-full root cause, but the runner aborts the workflow before the build step writes its first log line, so the symptom looks like a silent hang. | Check `ssh -p 2202 root@localhost df -h /` first when CI hangs. If <1 GB free, run `nix-collect-garbage -d` and re-push. |
| `build-vm` hangs at `Waiting for SSH...` indefinitely | Your ssh-agent has >5 keys loaded; sshd on the installer ISO hits `MaxAuthTries=6` before reaching `secrets/demo-ssh-key` | Ctrl-C the hang, then wrap the command in an isolated agent: `ssh-agent bash -c 'ssh-add secrets/demo-ssh-key; nix run .#build-vm -- -h <host> --identity-key secrets/demo-ssh-key ...'`. See the SSH agent note in Prerequisites. |

## Regenerate demo identity after `git clone`

```bash
bash secrets/regenerate-demo-identity.sh --force
```

See `secrets/README.md`.

## Pilot

You just ran the canonical signed-GitOps loop end-to-end. If you operate servers under NIS2, DORA, ISO 27001, or ANSSI BP-028 - whether on NixOS today or on Ansible / Puppet / Chef - we deliver the same loop on **your regulated zone** as a free 12-week pilot. 5 to 15 hosts; OS-layer migration in scope; auditor-ready evidence packet at month 3. The rest of your infrastructure stays where it is.

Scope, deliverables, and what we ask for in return: <https://arcanesys.fr/en/pilot>. Contact: <contact@arcanesys.fr>.

## References

- [nixfleet](https://github.com/arcanesys/nixfleet) v0.2.0 (pinned in `flake.nix`).
- [nixfleet-compliance](https://github.com/arcanesys/nixfleet-compliance) v0.2.0 - provides `compliance.nixosModules.nis2`.
- This repo: [github:arcanesys/nixfleet-demo](https://github.com/arcanesys/nixfleet-demo).
