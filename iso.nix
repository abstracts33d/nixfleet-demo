# Custom NixOS minimal ISO with the demo SSH key pre-configured.
#
# `nix run .#build-vm -- -h <host>` boots this ISO under QEMU, then
# nixos-anywhere SSHes in (using the baked-in key) to install the
# host's NixOS config to a fresh disk via disko.
#
# v0.2 removed `nixfleet.flakeModules.iso`; consumers absorb the
# module locally (see nixfleet's CHANGELOG "Removed").
{
  inputs,
  config,
  lib,
  ...
}: {
  options.nixfleet.isoSshKeys = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "SSH public keys baked into the installer ISO for passwordless root access.";
  };

  config.perSystem = {
    system,
    lib,
    ...
  }: let
    isLinux = builtins.elem system ["x86_64-linux" "aarch64-linux"];
    keys = config.nixfleet.isoSshKeys;
  in
    lib.optionalAttrs (isLinux && keys != []) {
      packages.iso = let
        isoSystem = inputs.nixpkgs.lib.nixosSystem {
          modules = [
            "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            {
              nixpkgs.hostPlatform = system;

              users.users.root.openssh.authorizedKeys.keys = keys;
              services.openssh = {
                enable = true;
                settings.PermitRootLogin = "prohibit-password";
              };

              services.qemuGuest.enable = true;
              services.spice-vdagentd.enable = true;

              environment.systemPackages = let
                pkgs = import inputs.nixpkgs {inherit system;};
              in [
                pkgs.git
                pkgs.parted
                pkgs.vim
              ];
            }
          ];
        };
      in
        isoSystem.config.system.build.isoImage;
    };
}
