# nixfleet-demo

Reference fleet implementation for [NixFleet](https://github.com/arcanesys/nixfleet)  - 6 persistent QEMU VMs demonstrating every framework scope with production-grade Nix modules.

## Hosts

| Host | Role | Scopes | Services |
|------|------|--------|----------|
| `cp-01` | Control plane | operators, o11y, compliance, impermanence, generation-label, terminal-compat | CP (TLS + mTLS), API key auth, nixfleet CLI |
| `web-01` | Web server | operators, o11y, compliance, impermanence, generation-label, terminal-compat | Agent (mTLS), nginx, node exporter, cache client |
| `web-02` | Web server | operators, o11y, compliance, impermanence, generation-label, terminal-compat | Agent (mTLS), nginx, node exporter, cache client |
| `db-01` | Database | operators, o11y, compliance, backup, generation-label, terminal-compat | Agent (mTLS), restic backup, node exporter, cache client |
| `mon-01` | Monitoring | operators, o11y, compliance, monitoring-server, generation-label, terminal-compat | Agent (mTLS), Prometheus server, node exporter, cache client |
| `cache-01` | Binary cache | operators, o11y, compliance, generation-label, terminal-compat | Harmonia cache server (port 5000) |

## Prerequisites

- NixOS or Nix with flakes enabled
- QEMU/KVM (`x86_64-linux`)
- ~10 GB RAM available (6 VMs)

## Quick Start

```bash
git clone https://github.com/arcanesys/nixfleet-demo
cd nixfleet-demo
```

**Before booting:** replace the placeholder SSH key with your own public key:

```bash
sed -i "s|ssh-ed25519 NixfleetDemoKeyReplaceWithYourOwn|$(cat ~/.ssh/id_ed25519.pub)|" \
  flake.nix modules/org-defaults.nix
```

Install and start all hosts:

```bash
# Install all hosts (cp-01 needs extra disk for building closures)
nix run .#build-vm -- --all --vlan 1234
nix run .#clean-vm -- -h cp-01
nix run .#build-vm -- -h cp-01 --vlan 1234 --disk-size 10G

# Start all hosts (cp-01 needs extra RAM for building closures)
nix run .#start-vm -- --all --vlan 1234
nix run .#stop-vm -- -h cp-01
nix run .#start-vm -- -h cp-01 --vlan 1234 --ram 4096
```

`--vlan 1234` gives VMs a shared network so they can reach each other by hostname. Without it, VMs are isolated  - SSH from host only.

SSH ports (deterministic from sorted host names):

| Host | SSH Port |
|------|----------|
| `cache-01` | 2201 |
| `cp-01` | 2202 |
| `db-01` | 2203 |
| `mon-01` | 2204 |
| `web-01` | 2205 |
| `web-02` | 2206 |

Stop and clean up:

```bash
# Stop all VMs
nix run .#stop-vm -- --all
# Delete all disks
nix run .#clean-vm -- --all
```

Login: `root` / `demo`

## Demo Walkthrough

> **SSH flags:** `-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null` is used throughout because VMs get new host keys on rebuild. **Do not use in production.**

### Connect to cp-01

The CLI and all fleet management runs from the control plane:

```bash
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2202 root@localhost
```

> All `nixfleet` commands below run inside cp-01.

The fleet configuration is baked into cp-01 at `/etc/nixfleet-demo/fleet`. All CLI commands use this as their flake source.

### Setup

```bash
# Pre-accept SSH host keys for all fleet hosts
ssh-keyscan cp-01 cache-01 web-01 web-02 db-01 mon-01 >> ~/.ssh/known_hosts 2>/dev/null

# Initialize CLI config (connection + cache settings)
nixfleet init \
  --control-plane-url https://localhost:8080 \
  --ca-cert /etc/nixfleet/fleet-ca.pem \
  --client-cert /run/agenix/cp-cert \
  --client-key /run/agenix/cp-key \
  --cache-url http://cache-01:5000 \
  --push-to ssh://cache-01

# Bootstrap the first admin API key
nixfleet bootstrap
```

`init` creates `.nixfleet.toml` with connection and cache settings. `bootstrap` generates the first admin API key and auto-saves it to `~/.config/nixfleet/credentials.toml`. All subsequent commands pick up both files automatically  - no env vars or repeated flags needed.

### Wait for Auto-Registration

Agents auto-register on their first health report (interval: 60s). Tags from NixOS config sync automatically.

```bash
# Watch machines register in real time (Ctrl+C when all 4 appear)
nixfleet machines list --watch
```

You should see 4 machines with lifecycle `active` and their tags (`web`, `db`, `monitoring`).

```bash
# Fleet overview  - shows machines, releases, and active rollouts
nixfleet status --watch
```

### Build, Push, and Deploy

> **First build is slow.** cp-01 has limited RAM and no binary cache yet, so it builds closures from source. Subsequent builds are fast once closures are cached on cache-01.

Preview what a deploy would do without applying:

```bash
# Dry run  - build closures and show the plan, but don't push or deploy
nixfleet deploy -v --dry-run --flake /etc/nixfleet-demo/fleet --tags web
```

Build closures, push to cache, and deploy via the control plane  - all in one command:

```bash
# Build, push to cache, create release, canary rollout, wait for completion
nixfleet deploy -v --flake /etc/nixfleet-demo/fleet --tags web --strategy canary --wait
```

This:
1. Builds web-01 and web-02 closures
2. Pushes closures to cache-01 (from `.nixfleet.toml` `[cache] push-to`)
3. Creates a release on the CP
4. Creates a canary rollout (1 host first, then the rest)
5. Waits for completion

Or step by step:

```bash
# Step 1: Create a release (build + push)
nixfleet release create --flake /etc/nixfleet-demo/fleet --hosts "web*"

# Step 2: Deploy the release
nixfleet deploy -v --release <RELEASE_ID> --tags web --strategy canary --wait
```

If you run `deploy` without `--wait`, the command exits after creating the rollout. Use `rollout status` to follow progress:

```bash
# Live rollout progress (Ctrl+C to exit)
nixfleet rollout status <ROLLOUT_ID> --watch
```

```bash
# Check fleet state after deploy
nixfleet status --watch

# Review past releases and rollouts
nixfleet release list
nixfleet rollout list
```

The agent on each web host will:
1. Fetch the closure from harmonia (`nix copy --from http://cache-01:5000`)
2. Apply via `switch-to-configuration switch`
3. Run health checks (HTTP on port 80)
4. Report success/failure to CP

<details><summary>Full commands with explicit flags (when running without .nixfleet.toml)</summary>

```bash
nixfleet deploy \
  --flake /etc/nixfleet-demo/fleet \
  --tags web \
  --push-to ssh://root@localhost:2201 \
  --cache-url http://cache-01:5000 \
  --strategy canary \
  --wait

# Or step by step:
nixfleet release create \
  --flake /etc/nixfleet-demo/fleet \
  --hosts "web*" \
  --push-to ssh://root@localhost:2201 \
  --cache-url http://cache-01:5000

nixfleet deploy \
  --release <RELEASE_ID> \
  --tags web \
  --strategy canary \
  --wait
```

</details>

### Direct SSH Deploy

Deploy a single host directly over SSH (no control plane needed):

```bash
# Deploy web-01 directly via SSH (bypasses CP orchestration)
nixfleet deploy --hosts web-01 --ssh \
  --target root@web-01 \
  --flake /etc/nixfleet-demo/fleet
```

### Test Failure Handling

```bash
# Break health check on web-01
ssh root@web-01 "systemctl stop nginx"

# Deploy with canary  - first batch should pause on health failure
nixfleet deploy -v --flake /etc/nixfleet-demo/fleet --tags web \
  --strategy canary --on-failure pause --health-timeout 60

# See the paused rollout and failed host
nixfleet status --watch
```

```bash
# Watch the rollout pause on health failure (Ctrl+C to exit)
nixfleet rollout status <ROLLOUT_ID> --watch

# Fix nginx on web-01
ssh root@web-01 "systemctl start nginx"

# Resume the paused rollout and watch completion
nixfleet rollout resume <ROLLOUT_ID>
nixfleet rollout status <ROLLOUT_ID> --watch
```

### Rollback via SSH

```bash
# Roll back web-01 to its previous generation
nixfleet rollback --host web-01 --ssh \
  --target root@web-01
```

### Useful Endpoints

```bash
# Nginx health (from the host itself)
ssh root@web-01 "curl -s http://localhost/health"
ssh root@web-02 "curl -s http://localhost/health"
```

## Architecture

```
                    mTLS (agent poll/report)
    ┌─────────┐ ◄──────────────────────► ┌──────────┐
    │ web-01  │                           │  cp-01   │
    │ web-02  │     agent ↔ CP cycle      │  (CP)    │
    │ db-01   │                           │  (CLI)   │
    │ mon-01  │                           └────┬─────┘
    └────┬────┘                                │
         │                                     │ /metrics (mTLS)
         │ :9100                          ┌────▼─────┐
         └────────────────────────────────► mon-01   │
                  node exporter scrape    │ (Prom)   │
                                          └──────────┘
    ┌──────────┐
    │ cache-01 │  ◄── nix copy --from (agents fetch closures)
    │(harmonia)│  ◄── nix copy --to (CLI pushes builds)
    │  :5000   │
    └──────────┘
```

## Auth Model

Agents authenticate via mTLS client certificates. Admin clients require both a client cert and an API key. See [ADR-007](https://github.com/arcanesys/nixfleet/blob/main/docs/adr/007-auth-route-split.md) for details.

## Secrets

Secrets are managed with [agenix](https://github.com/ryantm/agenix). A bootstrap age identity key is committed for demo convenience - **this is NOT a production pattern.** See the [NixFleet secrets guide](https://github.com/arcanesys/nixfleet/blob/main/docs/mdbook/guide/extending/secrets.md) for production recommendations.

All files under `secrets/` are pre-baked demo artifacts (TLS certs, passwords, signing keys). They are documented inline and can be regenerated - see `secrets/recipients.nix` for the full list. Root password: `demo`.

## Compliance

All hosts run [nixfleet-compliance](https://github.com/arcanesys/nixfleet-compliance) with NIS2 and ANSSI frameworks enabled. Run `compliance-check` on any host to see the posture report. See the [compliance repo](https://github.com/arcanesys/nixfleet-compliance) for framework details.

