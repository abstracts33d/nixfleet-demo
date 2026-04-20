# Inter-VM networking for QEMU VLAN.
# Assigns static IPs on eth1 (the VLAN NIC) and adds /etc/hosts
# so VMs can resolve each other by hostname.
#
# IP assignment follows sorted nixosConfigurations order (same as SSH ports):
#   cp-01=.1, db-01=.2, mon-01=.3, web-01=.4, web-02=.5, cache-01=.6
#
# Usage: nix run .#build-vm -- --all --vlan 1234
#        nix run .#start-vm -- --all --vlan 1234
{
  config,
  lib,
  ...
}: let
  vlanIps = {
    cp-01 = "10.0.100.1";
    db-01 = "10.0.100.2";
    mon-01 = "10.0.100.3";
    web-01 = "10.0.100.4";
    web-02 = "10.0.100.5";
    cache-01 = "10.0.100.6";
  };
  hostName = config.networking.hostName;
in {
  # QEMU VMs: use simple eth0/eth1 names (predictable names vary by kernel version)
  networking.usePredictableInterfaceNames = false;
  networking.useDHCP = lib.mkForce true;

  # Serial console for boot debugging (use start-vm with -nographic -serial mon:stdio)
  boot.kernelParams = ["console=ttyS0,115200n8"];

  networking.interfaces.eth1.ipv4.addresses = [
    {
      address = vlanIps.${hostName};
      prefixLength = 24;
    }
  ];

  networking.extraHosts = ''
    10.0.100.1 cp-01
    10.0.100.2 db-01
    10.0.100.3 mon-01
    10.0.100.4 web-01
    10.0.100.5 web-02
    10.0.100.6 cache-01
  '';
}
