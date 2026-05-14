# compliance-only — one host, signed evidence, no fleet

A single NixOS host running [nixfleet-compliance](https://github.com/arcanesys/nixfleet-compliance) standalone. No fleet, no control plane, no agent. The fastest way to see auditor-grade signed evidence without setting up a full signed-GitOps loop.

Four steps from clone to a verifying signature on screen:

```bash
cd compliance-only
nix run .
# (VM boots, lands at a root shell)
compliance-check
nixfleet-compliance-verify \
  --evidence  /var/lib/nixfleet-compliance/evidence.json \
  --signature /var/lib/nixfleet-compliance/evidence.json.sig \
  --pubkey    /var/lib/nixfleet-compliance/evidence.host.pub
```

The signed chain is real. The collector signs `evidence.json` with the host's SSH ed25519 key (`/etc/ssh/ssh_host_ed25519_key`) after every collection. The signature lives in `evidence.json.sig`. The public half lives next to it in `evidence.host.pub`. An auditor with those three files can verify the chain offline — no NixFleet integration required, no control plane, no operator trust.

## What this demo demonstrates

- **`nixfleet-compliance` runs on a single host.** No NixFleet-the-framework needed; no `mkFleet`, no agents, no control plane. Just one NixOS host with the module enabled.
- **The NIS2-essential preset activates the right controls** with regulatory-appropriate defaults (hourly probes, 15-min idle timeout, MFA required where applicable, baseline hardening).
- **The evidence chain is auditor-verifiable from the public side alone.** JCS-canonicalised (RFC 8785), ed25519-signed by the host SSH key, published alongside the host pubkey. `nixfleet-compliance-verify` reproduces the recipe end-to-end. Tamper the evidence file and verify exits 2 with a cryptographic failure — try it: `echo '{"host":"attacker"}' > /var/lib/nixfleet-compliance/evidence.json && nixfleet-compliance-verify ...`.
- **You don't have to be on NixOS already** to evaluate it. The bastion is one VM on your laptop. If it looks promising, the regulated zone of your real fleet (5–15 hosts) is the natural next scope. That's what the [12-week pilot](https://arcanesys.fr/en/pilot) covers.

## What this demo is NOT

- **Not a fleet demo.** For the full signed-GitOps loop (4 VMs, signed-artifact chain, wave promotion, magic rollback), see the parent [`../README.md`](../README.md) — that's a 10-step walkthrough on a 4-VM minimal reference fleet.
- **Not a production posture.** Root auto-login at the serial console, password-less. Fine for a 10-minute trial; do not deploy this configuration to production.
- **Not the full framework preset list.** This bastion enables NIS2-essential only. The module supports four presets (NIS2 / DORA / ISO 27001 / ANSSI BP-028) plus per-control overrides; see [the framework mappings](https://github.com/arcanesys/nixfleet-compliance/tree/main/docs) for the others.

## What to look at next

- `compliance-check --help` — the full CLI surface (read evidence, re-run probes inline with `--live`, verbose breakdown with `VERBOSE=1`). The reader branch also runs `nixfleet-compliance-verify` automatically when `.sig` + `.host.pub` are present and surfaces the result.
- `cat /var/lib/nixfleet-compliance/evidence.json | jq .` — the on-disk evidence shape. Format documented at [docs/evidence-format.md](https://github.com/arcanesys/nixfleet-compliance/blob/main/docs/evidence-format.md).
- `systemctl status compliance-evidence-collector` — the systemd timer that runs the probes. On NIS2-essential it runs hourly; on important entities, daily.
- `journalctl -u compliance-evidence-collector` — see what the collector produced last time.

## Exit the VM

Inside the QEMU console: press `Ctrl-A`, then `x` (twice).

## Next step

If this looks like a credible audit anchor for one of your regulated hosts, we run free 12-week pilots that take the same gate from "one bastion on your laptop" to "5–15 hosts in your regulated zone with an auditor-ready evidence packet at month 3". Details: <https://arcanesys.fr/en/pilot>. Contact: <contact@arcanesys.fr>.
