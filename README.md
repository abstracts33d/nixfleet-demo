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

SSH ports are auto-assigned by `mkVmApps` (alphabetical, `2201 + index`). Additional service ports are declared per-host via `hostSpec.vmPortForwards` (nixfleet [#87](https://github.com/arcanesys/nixfleet/issues/87)).

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

## 10-step walkthrough

### 1. Generate the demo identity (first clone only)

```bash
bash secrets/regenerate-demo-identity.sh
```

Generates everything the demo needs locally. Each file is either **public** (tracked in git so `nix flake check` works on a fresh clone) or **private** (gitignored, scp'd into the VMs at step 5 by `provision-secrets`):

| File | Visibility | Purpose |
|---|---|---|
| `secrets/demo-ssh-key.pub` | public | SSH pubkey for `git@forge` (push-repo). The private half is gitignored — `ssh -i` requires mode 0600 which git can't store |
| `secrets/recipients.nix` | public | age pubkey for agenix-style secrets |
| `secrets/org-root.pub.b64` | public | Org root pubkey — patched into `modules/trust.nix`; CP verifies bootstrap tokens against this |
| `secrets/fleet-ca.pem` | public | Fleet CA cert — also installed in each VM as the trust anchor for both directions of mTLS |
| `secrets/operator.pem` | public | Operator mTLS cert — clientAuth EKU, CN=`operator-demo@nixfleet-demo-cp`, 365d |
| `secrets/host-keys/web-{01,02}.pub` | public | Per-agent mTLS client pubkey — declared in `fleet.nix` so CP can match the CSR at `/v1/enroll` |
| `secrets/demo-ssh-key` | **private** | SSH private key for `git@forge` |
| `secrets/age-identity.txt` | **private** | age private identity |
| `secrets/org-root.pem` | **private** | Org root ed25519 PEM — used locally by `nixfleet mint-token` to sign bootstrap tokens; never leaves the operator workstation |
| `secrets/fleet-ca-key.pem` | **private** | Fleet CA private key — scp'd to `cp` only at step 5; CP signs agent + operator certs with it |
| `secrets/operator.key` | **private** | Operator mTLS private key — scp'd to `cp` at step 5 |
| `secrets/host-keys/web-{01,02}` | **private** | Per-agent mTLS client private key — scp'd to each web host at step 5 |
| `secrets/bootstrap-tokens/web-{01,02}.json` | **private** | One-shot enrollment tokens (168h validity), signed by the org root — scp'd to each web host at step 5 |

`cp.nix` / `web-NN.nix` reference these paths but never `builtins.readFile` the private halves, so the flake evaluates on a fresh clone without them. The `provision-secrets` app lands the private material into `/var/lib/nixfleet-demo/` in each VM after first boot.

> **PUBLIC keys.** Even regenerated locally, these are demo identities. **Do not deploy this fleet to production.**

> **Token validity.** Bootstrap tokens are valid for 168h (7 days) from generation. If first-boot enrollment lapses past this window, re-run the regenerator with `--force` and re-run `nix run .#provision-secrets -- --all` to ship fresh tokens.

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

> ⚠️ **Forge's release key is regenerated on every `clean-vm` of forge.** The keypair is in `/var/lib/nixfleet-release/`, which is wiped along with the qcow2. If you ever `clean-vm forge` later in the cycle, you MUST re-run `nix run .#fetch-release-key` AND rebuild `cp` + `web-01` + `web-02` (their closures bake the trust pin at build-vm time, so a rotated pin only takes effect after `build-vm --rebuild`). Skipping this is the #1 source of `BadSignature` errors in CP polling. See "Troubleshooting → BadSignature after clean-vm forge" below.

### 4. Boot the rest of the fleet

```bash
nix run .#start-vm -- -h cp --vlan 1234
nix run .#start-vm -- -h web-01 --vlan 1234
nix run .#start-vm -- -h web-02 --vlan 1234
```

`cp`, `web-01`, `web-02` build with the real pubkey from step 3 baked into `/etc/nixfleet/agent/trust.json`. `forge` continues running (mkVmApps no-ops on already-running VMs). Each host's RAM comes from its `hostSpec.vmRam`.

`--vlan 1234` puts every VM on a shared QEMU multicast L2 so they can resolve each other by hostname (`cp`, `forge`, `web-01`, `web-02`). The static IP and `/etc/hosts` wiring is in `modules/vm-network.nix`. All four VMs must use the same VLAN port number.

At this point the agent on `web-01`/`web-02` and the control plane on `cp` are **inert** — their systemd units have `ConditionPathExists=` on operator-private material that isn't in the closure. The next step lands it.

### 5. Provision operator-private material into each VM

```bash
nix run .#provision-secrets -- --all
```

scps the per-host private keys (fleet CA key + operator mTLS key for `cp`; agent identity key + bootstrap token for `web-01`/`web-02`) into `/var/lib/nixfleet-demo/`, then starts the previously gated services. **Private keys never enter the flake source tree** — `cp.nix` / `web-NN.nix` reference paths, not contents, so a fresh clone evaluates without them. The matching public halves (`.pub` files, `fleet-ca.pem`, `operator.pem`) ARE in git so `fleet.nix`'s `hosts.<n>.pubkey = builtins.readFile ./secrets/host-keys/<n>.pub` works at eval time.

If you don't run this step, agents log `nixfleet-agent.service: condition check resulted in skipped` and `nixfleet status` returns connection-refused.

### 6. Push the local repo into forge's Forgejo

```bash
nix run .#push-repo
```

Force-pushes the current branch to `git@localhost:2222/demo/fleet.git` (host port 2222 → guest port 222 via `vmPortForwards`). Forgejo Actions picks up the push, runs `.forgejo/workflows/ci.yml`, signs `releases/fleet.resolved.json` with the ed25519 key, commits the signature back to `main`. `cp` polls and verifies.

> **First CI run is slow.** The forge VM compiles the nixfleet Rust workspace from source (no attic priming on the demo) and builds all 4 hosts' `system.build.toplevel` from a cold nixpkgs cache. Expect 20-45 min on the first push. Subsequent pushes reuse forge's nix store and finish in 2-5 min. Watch progress: `ssh -p 2202 root@localhost 'journalctl -u gitea-runner-nixfleet -f --no-pager'`.

### 7. Watch convergence

```bash
ssh -p 2201 root@localhost          # SSH into cp
nixfleet status
nixfleet status --json              # emits raw HostsResponse for piping
```

The CLI picks up `NIXFLEET_CP_URL` / `NIXFLEET_CA_CERT` / `NIXFLEET_CLIENT_CERT` / `NIXFLEET_CLIENT_KEY` from cp's `environment.variables` — no `nixfleet config init` needed. The operator cert (`secrets/operator.pem`) is signed by the same fleet CA that issues agent certs.

> **`503 Service Unavailable` is expected before the first CI run completes.** CP gates `/v1/*` on the `artifact_primed` AND `revocations_primed` readiness flags (nixfleet#95). Until forge's CI signs the first `releases/fleet.resolved.json{,.sig}` and `releases/revocations.json{,.sig}`, CP has no verified artifact to serve and returns 503 for every operator/agent call. The 503 lifts within ~30s of CI committing the signed sidecars back to `main`. The first push triggers the cold-build CI run described in step 6 — plan on a coffee break.

All 4 hosts should report `Converged` within ~30s of CP turning ready (`web-02` first per `channelEdges`, then `web-01` after its 2-min soak). If they don't, see Troubleshooting below.

### 8. Confirm the web tier

```bash
curl http://localhost:2280/version   # web-01 → 1.0.0
curl http://localhost:2281/version   # web-02 → 1.0.0
```

### 9. Trigger a wave promotion

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

### 10. Cause a rollback

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

Removes per-host VM state including the qcow2 disks. The next time you want VMs, you must `build-vm` again first, **and re-rotate the release-signing trust pin before agents come up**:

```bash
# 1. Build forge FIRST and bring it up so its keygen oneshot regenerates
nix run .#build-vm -- -h forge --rebuild --identity-key secrets/demo-ssh-key
nix run .#start-vm -- -h forge --vlan 1234
nix run .#fetch-release-key                              # rotates trust.nix to forge's NEW key

# 2. ONLY NOW build the rest — they'll bake the rotated pin into their closure
nix run .#build-vm -- -h cp     --rebuild --identity-key secrets/demo-ssh-key
nix run .#build-vm -- -h web-01 --rebuild --identity-key secrets/demo-ssh-key
nix run .#build-vm -- -h web-02 --rebuild --identity-key secrets/demo-ssh-key
nix run .#start-vm -- -h cp     --vlan 1234
nix run .#start-vm -- -h web-01 --vlan 1234
nix run .#start-vm -- -h web-02 --vlan 1234

nix run .#provision-secrets -- --all
nix run .#push-repo
```

> ⚠️ **Order matters.** If you `build-vm cp/web-NN` BEFORE `fetch-release-key`, those closures bake the old (or placeholder) trust pin. CP then rejects every CI signature with `BadSignature`. The only fix is a second rebuild cycle. Wasted ~20 min per occurrence — don't skip step ordering.

`fetch-release-key` is idempotent: if forge's pubkey matches what `modules/trust.nix` already pins, it exits clean with no commit. After a fresh forge boot, it rotates to the new key and produces a `chore(demo): refresh release-signing pubkey` commit.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `push-repo` says "forge Forgejo SSH not reachable on 2222" | forge not booted, or disks were wiped by `clean-vm` and need `build-vm` again | `nix run .#build-vm -- -h forge --identity-key secrets/demo-ssh-key && nix run .#start-vm -- -h forge --vlan 1234` |
| `start-vm` says `[<host>] No disk found. Run build-vm first.` | `clean-vm` removed the qcow2; need to reinstall before booting | `nix run .#build-vm -- -h <host> --identity-key secrets/demo-ssh-key` |
| `fetch-release-key` says "did not surface key.pub within 60s" | First-boot keygen still running | `ssh -p 2202 root@localhost journalctl -u nixfleet-release-keygen -f` |
| CP log says `BadSignature` on revocations or fleet.resolved.json polls (`verify_revocations` / `verify_artifact`) | `forge` was wiped by a later `clean-vm`, regenerated its release keypair, but `cp`/`web-NN` closures still bake the OLD trust pin | Re-rotate + rebuild downstream: `nix run .#fetch-release-key && for h in cp web-01 web-02; do nix run .#clean-vm -- -h $h && nix run .#build-vm -- -h $h --rebuild --identity-key secrets/demo-ssh-key && nix run .#start-vm -- -h $h --vlan 1234; done && nix run .#provision-secrets -- --all && nix run .#push-repo`. This is the **#1 trap** in the demo — see "Cleanup" section for the correct ordering. |
| Agents log signature verification errors AND `trust.nix` has `wKiZ+...AAA=` (zero-pubkey placeholder) | First-time bootstrap never reached `fetch-release-key` | Run `nix run .#fetch-release-key`, then clean+rebuild cp + agent hosts as above |
| Agents log `enroll: 401` or `bootstrap-token expired` | Bootstrap token >168h old, or `modules/trust.nix` orgRootKey mismatch | `bash secrets/regenerate-demo-identity.sh --force`, then clean+rebuild affected web hosts |
| Agents log `enroll: 400 declared pubkey mismatch` | `secrets/host-keys/web-NN.pub` was regenerated but `fleet.nix`'s readFile cached, OR `/etc/ssh/ssh_host_ed25519_key` wasn't refreshed | Rebuild the host (`nix run .#build-vm -- -h web-NN --rebuild ...`) |
| `nixfleet status` shows hosts as `Stale` | `freshnessWindow` (120 min for this demo) exceeded; CI hasn't signed recently | Push again to retrigger CI |
| `nixfleet status` returns `503 Service Unavailable` | First CI run hasn't yet produced + signed `releases/fleet.resolved.json`; CP gates `/v1/*` on the readiness flags (nixfleet#95) | Wait for CI to finish — cold first run is 20-45 min |
| CI step fails with `error: writing to file: No space left on device` | Forge accumulates `/nix/store` paths from each CI run. Default qcow2 is 5G; after 3-4 cold-cycle runs it fills up | Either: clean-wipe forge (`stop-vm` + `clean-vm` + `build-vm -- -h forge --rebuild --disk-size 15G ...`) OR run `ssh -p 2202 root@localhost nix-collect-garbage -d` to GC older generations. The first push that re-warms after GC will take longer because some store paths must be rebuilt. |

## Regenerate demo identity after `git clone`

```bash
bash secrets/regenerate-demo-identity.sh --force
```

See `secrets/README.md`.

## Pilot

You just ran the canonical signed-GitOps loop end-to-end. If you operate servers under NIS2, DORA, ISO 27001, or ANSSI BP-028 — whether on NixOS today or on Ansible / Puppet / Chef — we deliver the same loop on **your regulated zone** as a free 12-week pilot. 5 to 15 hosts; OS-layer migration in scope; auditor-ready evidence packet at month 3. The rest of your infrastructure stays where it is.

Scope, deliverables, and what we ask for in return: <https://arcanesys.fr/en/pilot>. Contact: <contact@arcanesys.fr>.

## References

- nixfleet — **temporarily** pinned to the abstracts33d fork on github (`github:abstracts33d/nixfleet/v0.2.0`). Will swap to `github:arcanesys/nixfleet/v0.2.0` once that canonical org publishes the tag.
- nixfleet-compliance — **temporarily** pinned to the abstracts33d fork on github (`github:abstracts33d/nixfleet-compliance/v0.2.0`). Provides `compliance.nixosModules.nis2`. Same future-swap as nixfleet.
