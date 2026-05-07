# Demo-common config shared by all 4 VMs.
#
# Hardware setup (qemu-guest profile, virtio modules, btrfs disko layout)
# is provided by the framework when `isVm = true` — see nixfleet's
# tests/fixtures/qemu/{hardware-configuration,disk-config}.nix. This
# file only carries demo-specific defaults: serial console, root SSH
# via the demo key, firewall.
{lib, ...}: {
  imports = [../../modules/vm-network.nix];

  boot.kernelParams = ["console=ttyS0,115200"];
  services.getty.autologinUser = lib.mkDefault "root";
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "yes";
  services.openssh.settings.PasswordAuthentication = false;

  users.users.root.openssh.authorizedKeys.keyFiles = [
    ../../secrets/demo-ssh-key.pub
  ];

  networking.firewall.allowedTCPPorts = [22];
}
