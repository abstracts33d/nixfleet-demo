# Demo identity — PUBLIC, NOT FOR PRODUCTION

> **WARNING:** Every key produced here is a demo identity. The pubkeys
> live in git so `nix flake check` works on a fresh clone. The private
> halves are gitignored and regenerated locally — they remain demo
> material. Do NOT deploy this fleet to production without rotating
> every key in this directory.

## What lives here

| File | Tracked in git? | Purpose |
|---|---|---|
| `regenerate-demo-identity.sh` | yes | Generates the four files below. Run after every `git clone`. |
| `demo-ssh-key.pub` | yes | Baked into the installer ISO via `nixfleet.isoSshKeys` so root SSH works. |
| `recipients.nix` | yes | Age public key, imported by any agenix-aware module. |
| `demo-ssh-key` | **no** (gitignored) | SSH private key for `git@forge`. OpenSSH refuses keys with mode looser than 0600 and git can't store 0600, so this file isn't tracked. |
| `age-identity.txt` | **no** (gitignored) | age private key. Same reasoning. |

## First clone — required setup

```bash
bash secrets/regenerate-demo-identity.sh
```

The script:
1. Generates a fresh ed25519 SSH keypair at `secrets/demo-ssh-key{,.pub}` (mode 0600).
2. Generates a fresh age identity at `secrets/age-identity.txt` (mode 0600).
3. Writes `secrets/recipients.nix` with the matching age public key.

Existing tracked pubkey/recipient files are overwritten. To regenerate after the keys already exist locally, pass `--force`.

## Why this shape

OpenSSH and `ssh-add` refuse private keys with mode looser than 0600. Git's working-tree mode for tracked files defaults to 0644, and git only persists the executable bit (no support for 0600). So checking in the private keys would force every operator to `chmod 0600` after every clone — annoying friction for a demo.

Gitignoring the private halves and shipping a one-line generator script removes the chmod step entirely. Pubkeys stay in git (mode 0644 is fine for them) so that:
- `flake.nix` can `builtins.readFile` `secrets/demo-ssh-key.pub` for `nixfleet.isoSshKeys`,
- `nix flake check` works on a fresh clone,
- the `agenix` recipients block evaluates without a manual setup pass.

## Why public

The demo's purpose is to show a complete v0.2 GitOps loop end-to-end on 4 VMs with no external dependencies. That requires `forge` to accept SSH pushes immediately on first boot, which requires a known SSH key on the operator's side.

In production:
- Use agenix or sops with real recipients.
- Generate per-host SSH host keys at provisioning time.
- Rotate the release-signing key (the file-based ed25519 from forge is replaceable via `nixfleet.trust.ciReleaseKey.successor`).

## Pre-commit hook

`.githooks/pre-commit` whitelists files matching `secrets/demo-*` so the demo SSH public key can be committed. Anywhere else in the tree, an SSH public key in a diff still aborts the commit.
