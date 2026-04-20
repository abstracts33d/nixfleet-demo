# Contributing to NixFleet Demo

This is a reference implementation of a NixFleet-managed fleet. Contributions should improve the demo experience or fix bugs.

## Development Setup

**Prerequisites:**
- NixOS (or a Linux host with Nix)
- QEMU
- ~10 GB RAM for running the full fleet

**Getting started:**
```sh
git clone https://github.com/arcanesys/nixfleet-demo.git
cd nixfleet-demo
nix develop  # enters the dev shell
nix fmt       # format all Nix files
```

## Extending the Demo

**Add a host:**
1. Create `hosts/<name>/` with `default.nix`, `hardware.nix`, and `disk.nix`
2. Add an entry to `fleet.nix`

**Add a module:**
1. Create `modules/<name>.nix`
2. Import it in the relevant host definitions

**Add a secret:**
1. Encrypt with `agenix -e secrets/<name>.age`
2. Add the recipient to `secrets/recipients.nix`

## Commit Conventions

Use [conventional commits](https://www.conventionalcommits.org/):

- `feat:` - new feature
- `fix:` - bug fix
- `docs:` - documentation only
- `chore:` - maintenance

## License

By submitting a pull request, you agree to license your contribution under the [MIT License](LICENSE-MIT).
