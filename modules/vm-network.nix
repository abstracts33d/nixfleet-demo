# Inter-VM networking for the QEMU multicast VLAN that mkVmApps
# enables with `--vlan PORT`. Assigns static IPs on eth1 (the VLAN
# NIC) and populates /etc/hosts so VMs resolve each other by hostname.
#
# IP allocation follows sorted nixosConfigurations order (same as
# mkVmApps' SSH-port assignment):
#   cp     = 10.0.100.1
#   forge  = 10.0.100.2
#   web-01 = 10.0.100.3
#   web-02 = 10.0.100.4
#
# Usage:
#   nix run .#start-vm -- --all --vlan 1234
#
# Without --vlan, eth1 doesn't exist and the address assignment is a
# no-op (NixOS allows config for non-existent interfaces; the kernel
# silently doesn't apply it). The extraHosts entries still resolve;
# they just don't reach anywhere.
{
  config,
  lib,
  ...
}: let
  vlanIps = {
    cp = "10.0.100.1";
    forge = "10.0.100.2";
    web-01 = "10.0.100.3";
    web-02 = "10.0.100.4";
  };
  hostName = config.networking.hostName;
in {
  # mkVmApps QEMU images: predictable interface names break across
  # kernel versions, so use the unstable eth0/eth1 names instead.
  networking.usePredictableInterfaceNames = false;
  networking.useDHCP = lib.mkForce true;

  networking.interfaces.eth1.ipv4.addresses = lib.optional (vlanIps ? ${hostName}) {
    address = vlanIps.${hostName};
    prefixLength = 24;
  };

  networking.extraHosts = ''
    10.0.100.1 cp
    10.0.100.2 forge
    10.0.100.3 web-01
    10.0.100.4 web-02
  '';
}
