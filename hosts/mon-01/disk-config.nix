# Standard btrfs - QEMU /dev/vda (no impermanence).
{
  lib,
  inputs,
  ...
}:
import inputs.nixfleet-scopes.scopes.disk-templates.btrfs {inherit lib;}
