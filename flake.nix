{
  description = "nixfleet-demo — v0.2 minimal reference fleet";

  inputs = {
    # TEMPORARY: pinned to abstracts33d's fork on github (publicly mirrored
    # from lab/main). Once v0.2 ships on the canonical arcanesys org, swap to:
    #   nixfleet.url = "github:arcanesys/nixfleet/<v0.2-tag>";
    # The fork mirror sidesteps the lab Caddy CA — public github uses
    # publicly-trusted CAs so the runner VM doesn't need extra trust roots.
    nixfleet.url = "github:abstracts33d/nixfleet?rev=0964174a654d5032f26c9e4ef425aeeda5d99407";
    nixpkgs.follows = "nixfleet/nixpkgs";
    flake-parts.follows = "nixfleet/flake-parts";
    treefmt-nix.follows = "nixfleet/treefmt-nix";
    attic = {
      url = "github:booxter/attic/newer-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # TEMPORARY: same fork-mirror story as nixfleet above. Swap to
    # `github:arcanesys/nixfleet-compliance` once v0.2 ships there.
    compliance = {
      url = "github:abstracts33d/nixfleet-compliance?rev=52c8a169f354127b45111832cb31d12e81b6d07f";
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
