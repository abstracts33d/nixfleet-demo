{
  description = "NixFleet Demo Fleet - reference implementation";

  inputs = {
    nixfleet.url = "github:arcanesys/nixfleet";
    nixfleet-scopes = {
      url = "github:arcanesys/nixfleet-scopes";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixfleet.inputs.nixfleet-scopes.follows = "nixfleet-scopes";
    nixpkgs.follows = "nixfleet/nixpkgs";
    home-manager.follows = "nixfleet/home-manager";
    disko.follows = "nixfleet/disko";
    impermanence.follows = "nixfleet/impermanence";
    compliance = {
      url = "github:arcanesys/nixfleet-compliance";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts.follows = "nixfleet/flake-parts";
    treefmt-nix.follows = "nixfleet/treefmt-nix";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        ./fleet.nix
        ./apps.nix
        inputs.nixfleet.flakeModules.iso
        inputs.nixfleet.flakeModules.formatter
      ];
      systems = ["x86_64-linux"];

      # SSH keys baked into the installer ISO for automated installs
      nixfleet.isoSshKeys = [
        "ssh-ed25519 NixfleetDemoKeyReplaceWithYourOwn"
      ];
    };
}
