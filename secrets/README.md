# Demo identity - PUBLIC, NOT FOR PRODUCTION

> **WARNING:** Every key in this directory is a demo identity, committed
> to git on purpose. Do NOT deploy this fleet to production without
> rotating every key here.

## Policy

Every file in `secrets/` is committed (both halves of every keypair, the
CA private, the bootstrap tokens, the operator cert, etc). A fresh clone
boots a working demo without running anything special - just
`nix run .#fleet-up`.

The PUBLIC-by-design framing is the whole point: the demo's value is
that you can `git clone` and watch the fleet behave, with no external
secrets infrastructure. Real deployments must rotate every key here.

## What lives here

| File | Purpose |
|---|---|
| `demo-ssh-key{,.pub}` | SSH keypair for `git@forge`. |
| `age-identity.txt` | age private key. |
| `recipients.nix` | age recipient list, imported by agenix modules. |
| `org-root.pem` + `.pub.b64` | Signs bootstrap tokens. CP verifies via `nixfleet.trust.orgRootKey.current`. |
| `fleet-ca.pem` + `fleet-ca-key.pem` | P-256 root CA. Signs CP TLS, agent client certs, operator certs. |
| `host-keys/<host>{,.pub}` | Per-host SSH host key + mTLS client key. |
| `bootstrap-tokens/<host>.json` | One-shot enrollment tokens (10y validity). |
| `bootstrap-nonces.nix` | Allowlist mirrored into `fleet.bootstrapNonces`. |
| `cache-signing-key{,.pub}` | Harmonia signing keypair. |
| `operator.pem` + `operator.key` | Operator mTLS cert (365d). |
| `regenerate-demo-identity.sh` | Optional rotation tool. |

All files form a self-consistent set: the CA signs the host/operator
certs, org-root signs the bootstrap tokens, etc. Rotating one without
the others breaks enrollment.

## Rotating the demo identity

```bash
bash secrets/regenerate-demo-identity.sh --force
```

This re-mints every key + token + cert and patches
`modules/trust.nix:orgRootKey.current` to match. Useful if you suspect
the public demo identity has been "burned" by someone running this on
the open internet, or if you want to test the rotation flow.

After regenerating, commit the diff if you want the rotated identity to
be the new baseline. Or discard it (`git checkout secrets/ modules/trust.nix`)
to revert to the committed baseline.

## File modes

`ssh-add` and `age-keygen` refuse private keys with mode looser than
0600. git's checkout default is 0644 (it only records the executable
bit). `nix run .#fleet-up`'s Step 0 enforces 0600 on
`secrets/demo-ssh-key` and `secrets/age-identity.txt` every run, so
operators never have to think about it.

## Pre-commit hook

`.githooks/pre-commit` whitelists files matching `secrets/*` so demo
keys can be committed. Anywhere else in the tree, an SSH public key in
a diff aborts the commit.
