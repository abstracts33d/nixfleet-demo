# Running the demo from macOS

The demo boots Linux VMs via QEMU/KVM. macOS exposes no `/dev/kvm`, so `nix run github:arcanesys/nixfleet-demo` will refuse to start on Apple Silicon or Intel Macs.

Three workable paths.

## 1. Run from a Linux machine (cheapest)

Any Linux box with Nix installed (flakes enabled) and `/dev/kvm` accessible works. SSH into it from your Mac and run the demo there.

```
ssh you@linux-box
nix run github:arcanesys/nixfleet-demo
```

## 2. Linux VM on the Mac (most local)

Run a small Linux guest under one of:

- [UTM](https://mac.getutm.app/) -- free, QEMU-based
- [OrbStack](https://orbstack.dev/) -- macOS-native, fast
- [Lima](https://lima-vm.io/) -- CLI-only, scriptable

Inside that guest: install Nix, enable flakes, ensure the guest has nested virtualisation or accept that the inner demo VM falls back to TCG (slow but boots).

## 3. nix-darwin linux-builder (most native)

If you already run [nix-darwin](https://github.com/LnL7/nix-darwin) with the `nix.linux-builder` module, the build pipeline transparently delegates to a managed Linux remote builder. The `nixosConfigurations.bastion.config.system.build.vm` derivation builds there.

This does NOT run the resulting VM on the Mac (KVM still missing), but it gives you the artefact. To boot it, either:

- copy the `run-bastion-vm` script to a Linux host with KVM
- or use the linux-builder's underlying VM as the runtime (advanced)

For most users, options 1 and 2 are simpler.

## Why no macOS-native path?

The demo's value is showing a real NixOS host producing signed evidence in a real qemu-vm. macOS virtualisation frameworks (Hypervisor.framework, Virtualization.framework) work, but the NixOS qemu-vm wrapper is wired for KVM and there is no clean shim. A macOS-native path is out of scope for the reference demo; the three options above all work today.
