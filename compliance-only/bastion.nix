# bastion: standalone hardened NixOS host with NIS2-essential compliance.
#
# This host is NOT part of any fleet. nixfleet-compliance runs on a single
# NixOS host with no control plane, no agent, no orchestration. Boot, log
# in at the console, run `compliance-check`, inspect signed evidence.
#
# Designed to come up in <60 seconds with zero provisioning. The point is
# to make the evidence chain tangible: a hostname + a date + a signature
# an auditor can verify offline.
{
  pkgs,
  lib,
  modulesPath,
  ...
}: {
  imports = ["${modulesPath}/virtualisation/qemu-vm.nix"];

  # Demo VM defaults: 1 GiB RAM, 4 GiB disk, serial console.
  virtualisation.memorySize = 1024;
  virtualisation.diskSize = 4096;
  virtualisation.graphics = false;

  boot.kernelParams = ["console=ttyS0,115200"];

  # No SSH dance for the demo -- auto-login as root at the serial
  # console. The whole point is "run one command, see evidence".
  services.getty.autologinUser = lib.mkForce "root";
  users.users.root.initialHashedPassword = "";

  networking.hostName = "bastion";
  networking.firewall.enable = false; # demo VM, no external exposure

  # NIS2-essential preset: hourly probes, 15-min idle timeout, MFA
  # required where applicable. This is what produces the signed evidence.
  compliance.frameworks.nis2 = {
    enable = true;
    entityType = "essential";
  };
  compliance.governance.hostType = "server";

  # The CLI is installed by the compliance module activation; jq is for
  # the operator's pretty-printing reflex when poking at evidence.json.
  environment.systemPackages = [pkgs.jq];

  # Tag the shell with what to do first.
  environment.etc."motd".text = ''

    nixfleet-compliance demo - single NixOS host, NIS2-essential
    =============================================================

    No fleet, no control plane, no agent. One NixOS host, signed
    evidence on disk under /var/lib/nixfleet-compliance/.

    Run these four commands in order:

      1. compliance-check
           Read the latest signed evidence, verify the signature
           against the published pubkey, print the control table.

      2. nixfleet-compliance-verify
           Same chain end-to-end via the standalone auditor tool.
           Defaults to the canonical paths in /var/lib/nixfleet-compliance/.
           Exits 0 on success, 2 on failure.

      3. echo '{"host":"attacker"}' > /var/lib/nixfleet-compliance/evidence.json
         nixfleet-compliance-verify
           Tamper test. Expect exit 2 ("signature verification failed").

      4. systemctl start compliance-evidence-collector
           Restore real signed evidence after the tamper test.

    Look further:
      compliance-check --help
      cat /var/lib/nixfleet-compliance/evidence.json | jq .
      journalctl -u compliance-evidence-collector

    An auditor handed this host's name and the public key at
    /var/lib/nixfleet-compliance/evidence.host.pub verifies the chain
    offline -- no operator trust, no scanner vendor.

    Exit the VM: Ctrl-A then x (twice).

  '';

  system.stateVersion = "26.05";
}
