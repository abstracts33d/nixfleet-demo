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
                settings = {
                  PermitRootLogin = "prohibit-password";
                  # OpenSSH 10.0+ enables PerSourcePenalties by default --
                  # it penalises source IPs that make multiple connections
                  # and disconnect (which is exactly nixos-anywhere's
                  # pattern: many parallel SSH connections from localhost
                  # during ssh-copy-id, fact gathering, disko, copy-closure).
                  # The "Not allowed at this time" rejection on the second
                  # and subsequent ssh-copy-id attempts is the penalty
                  # kicking in, NOT MaxStartups. Disable it so nixos-anywhere
                  # can drive the install without the source-IP throttle.
                  PerSourcePenalties = "no";
                  # Belt-and-suspenders for any future / nested limit:
                  MaxStartups = "100:30:200";
                  MaxSessions = 100;
                  MaxAuthTries = 20;
                  LoginGraceTime = 600;
                };
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
