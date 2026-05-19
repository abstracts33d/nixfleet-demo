# Demo-common config shared by all 4 VMs.
#
# Hardware setup (qemu-guest profile, virtio modules, btrfs disko layout)
# is provided by the framework when `isVm = true` - see nixfleet's
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
  # OpenSSH 10.0+ enables PerSourcePenalties by default, which penalises
  # source IPs that make multiple connections and disconnect.
  # provision-secrets and push-repo open several short-lived SSH
  # connections from localhost in quick succession, which trips the
  # penalty and causes "Connection closed" failures. The same
  # mitigation already lives in iso.nix for the installer ISO.
  services.openssh.settings.PerSourcePenalties = "no";

  users.users.root.openssh.authorizedKeys.keyFiles = [
    ../../secrets/demo-ssh-key.pub
  ];

  networking.firewall.allowedTCPPorts = [22];
}
