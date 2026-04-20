# VM lifecycle apps from nixfleet framework.
# launch-fleet / stop-fleet are replaced by:
#   nix run .#build-vm -- --all     (install all hosts)
#   nix run .#start-vm -- --all     (boot all as daemons)
#   nix run .#stop-vm -- --all      (stop all)
#   nix run .#clean-vm -- --all     (delete all disks)
{inputs, ...}: {
  perSystem = {pkgs, ...}: {
    apps = inputs.nixfleet.lib.mkVmApps {inherit pkgs;};
  };
}
