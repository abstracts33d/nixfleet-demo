{
  description = "nixfleet-demo - v0.2 minimal reference fleet";

  inputs = {
    nixfleet.url = "github:arcanesys/nixfleet/v0.2.0";
    nixpkgs.follows = "nixfleet/nixpkgs";
    flake-parts.follows = "nixfleet/flake-parts";
    treefmt-nix.follows = "nixfleet/treefmt-nix";
    compliance = {
      url = "github:arcanesys/nixfleet-compliance/v0.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];

      imports = [
        ./fleet.nix
        ./apps.nix
        ./formatter.nix
        ./iso.nix
      ];

      # Demo SSH key baked into the installer ISO so build-vm's
      # nixos-anywhere SSH can authenticate as root during install.
      nixfleet.isoSshKeys = [
        (builtins.readFile ./secrets/demo-ssh-key.pub)
      ];

      # Fleet members (cp, web-01, web-02) are built by the framework's
      # mkFleet → nixosConfigurations wrapper (RFC-0011 §2.2 + 9e). The
      # per-host args live in fleet.nix as `hosts.<n>.nixosArgs`, sourced
      # from `./hosts/<n>.nix`. forge is intentionally outside the fleet
      # and goes through the manual-mkHost path documented in
      # `./hosts/forge.nix`. mkVmApps assigns SSH ports alphabetically
      # over `attrNames` of this attrset, so the final order is
      # cp(2201) / forge(2202) / web-01(2203) / web-02(2204).
      flake.nixosConfigurations =
        inputs.self.fleet.nixosConfigurations
        // {
          forge = import ./hosts/forge.nix {
            inherit inputs;
            self = inputs.self;
          };
        };

      # The bastion (single-host compliance demo) is intentionally NOT in
      # flake.nixosConfigurations: nixfleet's mkVmApps assigns SSH host
      # ports by alphabetically iterating that attrset, so adding a 5th
      # entry would shift every fleet host's port by +1. Instead it lives
      # as a package; apps.default builds it via that path. The same
      # configuration is also exposed standalone by compliance-only/flake.nix.

      # Darwin stubs: nix run resolves but prints a clear "needs Linux"
      # message instead of failing cryptically on missing /dev/kvm.
      # Kept out of perSystem so the Linux apps don't have to evaluate
      # cross-platform.
      flake.apps = let
        mkDarwinStub = darwinSystem: let
          darwinPkgs = inputs.nixpkgs.legacyPackages.${darwinSystem};
          stub = darwinPkgs.writeShellApplication {
            name = "nixfleet-demo-macos";
            runtimeInputs = [];
            text = ''
                            cat >&2 <<'EOF'
              The nixfleet-demo boots Linux VMs via QEMU/KVM. macOS does not provide
              /dev/kvm, so the demo can't run directly on Apple Silicon or Intel Macs.

              Options:
                1. Run from any Linux machine (cheapest).
                2. Use nix-darwin's linux-builder to delegate VM builds to a Linux
                   remote builder, then connect to the resulting console manually.
                3. Run inside a Linux VM on your Mac (UTM, OrbStack, Lima).

              See docs/macos.md in the repo for the full write-up.
              EOF
                            exit 1
            '';
          };
        in {
          default = {
            type = "app";
            program = "${stub}/bin/nixfleet-demo-macos";
            meta.description = "macOS stub: this demo needs a Linux host with KVM.";
          };
          fleet = {
            type = "app";
            program = "${stub}/bin/nixfleet-demo-macos";
            meta.description = "macOS stub: this demo needs a Linux host with KVM.";
          };
        };
      in {
        aarch64-darwin = mkDarwinStub "aarch64-darwin";
        x86_64-darwin = mkDarwinStub "x86_64-darwin";
      };
    };
}
