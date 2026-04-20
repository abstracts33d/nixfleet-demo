# Btrfs with impermanence - QEMU /dev/vda.
{
  lib,
  inputs,
  ...
}: {
  disko.devices = import inputs.nixfleet-scopes.scopes.disk-templates.btrfs-impermanence {inherit lib;};
}
