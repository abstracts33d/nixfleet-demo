# Fleet-wide compliance - NIS2 + ANSSI frameworks with governance.
#
# Usage in fleet.nix: (import ./modules/compliance.nix {inherit inputs;})
# Returns a NixOS module (the outer function captures inputs,
# the inner function is the standard NixOS module signature).
{inputs}: {...}: {
  imports = [
    inputs.compliance.nixosModules.nis2
    inputs.compliance.nixosModules.anssi
    inputs.compliance.nixosModules.governance
    inputs.compliance.nixosModules.compliance-check
  ];

  compliance.frameworks.nis2 = {
    enable = true;
    entityType = "essential";
  };

  compliance.frameworks.anssi.enable = true;
}
