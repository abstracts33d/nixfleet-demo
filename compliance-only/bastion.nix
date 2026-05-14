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

    No fleet, no control plane, no agent. Just one NixOS host running
    nixfleet-compliance.

    Read the evidence:
      compliance-check         # latest signed evidence + signature status
      compliance-check --help  # full CLI
      VERBOSE=1 compliance-check  # full per-check breakdown for FAILs

    Verify the evidence chain end-to-end (the auditor's recipe):
      nixfleet-compliance-verify \
        --evidence  /var/lib/nixfleet-compliance/evidence.json \
        --signature /var/lib/nixfleet-compliance/evidence.json.sig \
        --pubkey    /var/lib/nixfleet-compliance/evidence.host.pub

    Try the tamper test:
      echo '{"host":"attacker"}' > /var/lib/nixfleet-compliance/evidence.json
      nixfleet-compliance-verify --evidence ... --signature ... --pubkey ...
      # -> FAIL  signature verification: ed25519 verification failed
      # (then: systemctl start compliance-evidence-collector to restore real evidence)

    The on-disk shape:
      ls /var/lib/nixfleet-compliance/
      cat /var/lib/nixfleet-compliance/evidence.json | jq .

    The collector:
      systemctl status compliance-evidence-collector
      systemctl start  compliance-evidence-collector  # force a fresh collection

    The point: an auditor handed this host's name and the published pubkey
    (/var/lib/nixfleet-compliance/evidence.host.pub) can verify the chain
    offline -- without trusting you, the operator, or any scanner vendor.

  '';

  system.stateVersion = "26.05";
}
