# cp: nixfleet control plane.
#
# Polls forge's git for fleet.resolved.json + signature. Validates against
# the ed25519 pubkey declared in modules/trust.nix. Dispatches rollout actions
# to agents per channel/wave/edge policies declared in fleet.nix.
#
# Compliance: NIS2 essential (the demo's compliance posture demonstration).
{inputs, ...}:
inputs.nixfleet.lib.mkHost {
  hostName = "cp";
  platform = "x86_64-linux";
  isVm = true;
  hostSpec = {
    userName = "root";
    timeZone = "UTC";
    locale = "en_US.UTF-8";
    vmPortForwards = {
      "8443" = 8443; # control plane TLS
    };
    # Compliance probes + reconciler state are tighter than the 1024 default.
    vmRam = 2048;
  };
  modules = [
    ./_shared/qemu-vm.nix
    ../modules/trust.nix
    inputs.nixfleet.scopes.persistence.impermanence
    inputs.compliance.nixosModules.nis2
    (
      {pkgs, ...}: {
        services.nixfleet-control-plane = {
          enable = true;
          listen = "0.0.0.0:8443";
          openFirewall = true;
          tls.cert = "/var/lib/nixfleet-control-plane/tls/cert.pem";
          tls.key = "/var/lib/nixfleet-control-plane/tls/key.pem";

          # Poll forge's Forgejo HTTP. Inter-VM hostname resolution is
          # via the multicast VLAN configured by `start-vm --vlan 1234`
          # + the static-IP/extraHosts wiring in modules/vm-network.nix.
          channelRefsSource = {
            artifactUrl = "http://forge:3001/demo/fleet/raw/branch/main/releases/fleet.resolved.json";
            signatureUrl = "http://forge:3001/demo/fleet/raw/branch/main/releases/fleet.resolved.json.sig";
          };

          # Empty list is a steady state for the demo. CP still verifies the
          # (empty) signed revocations artifact — exercises gap C.
          revocationsSource = {
            artifactUrl = "http://forge:3001/demo/fleet/raw/branch/main/releases/revocations.json";
            signatureUrl = "http://forge:3001/demo/fleet/raw/branch/main/releases/revocations.json.sig";
          };
        };

        # Self-sign a CP TLS cert on first boot. Demo-only — production
        # would wire these paths to a secrets backend (agenix, sops) or
        # to an ACME-issued cert via the reverse-proxy scope.
        systemd.services.nixfleet-cp-tls-keygen = {
          description = "First-boot self-signed TLS cert for nixfleet-control-plane";
          wantedBy = ["multi-user.target"];
          before = ["nixfleet-control-plane.service"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "root";
            UMask = "0027";
          };
          script = ''
            set -euo pipefail
            tls_dir=/var/lib/nixfleet-control-plane/tls
            mkdir -p "$tls_dir"
            cert="$tls_dir/cert.pem"
            key="$tls_dir/key.pem"
            if [ ! -f "$cert" ] || [ ! -f "$key" ]; then
              ${pkgs.openssl}/bin/openssl req -x509 -newkey ed25519 -nodes \
                -keyout "$key" -out "$cert" -days 3650 \
                -subj "/CN=cp.demo.invalid" \
                -addext "subjectAltName=DNS:cp,DNS:cp.demo.invalid,IP:127.0.0.1"
              chmod 0600 "$key"
              chmod 0644 "$cert"
            fi
          '';
        };

        compliance.frameworks.nis2 = {
          enable = true;
          entityType = "essential";
        };
        compliance.governance.hostType = "server";

        # nixfleet-cli for `nixfleet status` on cp.
        environment.systemPackages = [
          inputs.nixfleet.packages.x86_64-linux.nixfleet-cli
          pkgs.jq
        ];

        nixfleet.persistence.directories = [
          "/var/lib/nixfleet-control-plane"
          "/var/lib/nixfleet-compliance"
        ];
      }
    )
  ];
}
