{
  description = "nixfleet-demo — v0.2 minimal reference fleet";

  inputs = {
    # Pinned to abstracts33d's public github fork at v0.2.0. Will swap to
    # `github:arcanesys/nixfleet/v0.2.0` once the canonical org publishes.
    # The fork sidesteps the lab Caddy CA — public github uses publicly-
    # trusted CAs so the runner VM doesn't need extra trust roots.
    nixfleet.url = "github:abstracts33d/nixfleet/v0.2.0";
    nixpkgs.follows = "nixfleet/nixpkgs";
    flake-parts.follows = "nixfleet/flake-parts";
    treefmt-nix.follows = "nixfleet/treefmt-nix";
    attic = {
      url = "github:booxter/attic/newer-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Same fork-mirror story as nixfleet above. Swap to
    # `github:arcanesys/nixfleet-compliance/v0.2.0` once that org publishes.
    compliance = {
      url = "github:abstracts33d/nixfleet-compliance/v0.2.0";
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

      flake.nixosConfigurations = {
        forge = import ./hosts/forge.nix {
          inherit inputs;
          self = inputs.self;
        };
        cp = import ./hosts/cp.nix {
          inherit inputs;
          self = inputs.self;
        };
        web-01 = import ./hosts/web-01.nix {
          inherit inputs;
          self = inputs.self;
        };
        web-02 = import ./hosts/web-02.nix {
          inherit inputs;
          self = inputs.self;
        };
      };
    };
}
