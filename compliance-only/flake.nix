{
  description = "nixfleet-compliance demo — one NixOS host, signed evidence, no fleet";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Temporary mirror pin; will swap to
    # `github:arcanesys/nixfleet-compliance/v0.2.0` once that org publishes
    # (same swap timing as the parent fleet demo).
    compliance = {
      url = "github:abstracts33d/nixfleet-compliance/v0.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    compliance,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    # Standalone NixOS host -- no fleet, no agent, no control plane.
    # Demonstrates that nixfleet-compliance runs on a single hardened
    # NixOS host and produces auditor-grade signed evidence by itself.
    nixosConfigurations.bastion = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        compliance.nixosModules.nis2
        ./bastion.nix
      ];
    };

    # `nix run .` builds the VM, boots it, drops you at a root shell.
    # Type `compliance-check` once inside; see signed evidence.
    apps.${system}.default = let
      run = pkgs.writeShellApplication {
        name = "run-bastion";
        runtimeInputs = [pkgs.nix];
        text = ''
          set -euo pipefail
          echo ""
          echo "=== nixfleet-compliance demo (one host, no fleet) ==="
          echo ""
          echo "Building bastion VM (single NixOS host, NIS2-essential preset, no fleet)..."
          nix build --print-build-logs .#nixosConfigurations.bastion.config.system.build.vm
          echo ""
          echo "Booting. Console login: root (no password)."
          echo "Once at the shell, try:"
          echo "  compliance-check         # read the latest signed evidence"
          echo "  compliance-check --help  # full CLI"
          echo "  cat /var/lib/nixfleet-compliance/evidence.json | jq ."
          echo "  systemctl status compliance-evidence-collector"
          echo ""
          echo "To exit the VM: Ctrl-A then 'x' (twice)."
          echo ""
          ./result/bin/run-nixos-vm
        '';
      };
    in {
      type = "app";
      program = "${run}/bin/run-bastion";
      meta.description = "Build + boot the standalone compliance-only NixOS bastion VM";
    };

    formatter.${system} = pkgs.alejandra;
  };
}
