# web-02: edge-channel web agent.
#
# Identical to web-01 except for hostName + token/host-key paths.
# Channel assignment (`channel = "edge"`) lives in fleet.nix.
#
# /version returns "1.0.0\n" via modules/web-version.nix (shared with web-01).
# See web-01.nix for the first-boot enrollment flow rationale.
{inputs, ...}:
inputs.nixfleet.lib.mkHost {
  hostName = "web-02";
  platform = "x86_64-linux";
  isVm = true;
  hostSpec = {
    userName = "root";
    timeZone = "UTC";
    locale = "en_US.UTF-8";
    vmPortForwards = {
      "80" = 2281; # nginx
    };
  };
  modules = [
    ./_shared/qemu-vm.nix
    ../modules/trust.nix
    ../modules/web-version.nix
    inputs.nixfleet.scopes.persistence.impermanence
    inputs.compliance.nixosModules.nis2
    {
      services.nixfleet-agent = {
        enable = true;
        controlPlaneUrl = "https://cp:8443";
        tags = ["web"];
        tls.caCert = "/etc/nixfleet-demo/fleet-ca.pem";
        bootstrapTokenFile = "/var/lib/nixfleet/bootstrap-token";
        healthChecks = {
          mode = "enforce";
          http = [
            {
              name = "nginx-version";
              url = "http://localhost/version";
              expectStatus = 200;
              intervalSeconds = 15;
              timeoutSeconds = 3;
            }
          ];
        };
      };

      environment.etc."ssh/ssh_host_ed25519_key" = {
        text = builtins.readFile ../secrets/host-keys/web-02;
        mode = "0600";
      };
      environment.etc."ssh/ssh_host_ed25519_key.pub" = {
        text = builtins.readFile ../secrets/host-keys/web-02.pub;
        mode = "0644";
      };
      environment.etc."nixfleet-demo/fleet-ca.pem" = {
        text = builtins.readFile ../secrets/fleet-ca.pem;
        mode = "0644";
      };
      environment.etc."nixfleet-demo/bootstrap-token.json" = {
        text = builtins.readFile ../secrets/bootstrap-tokens/web-02.json;
        mode = "0644";
      };

      systemd.services.nixfleet-agent-bootstrap-token = {
        description = "Stage one-shot bootstrap token for nixfleet-agent enrollment";
        wantedBy = ["multi-user.target"];
        before = ["nixfleet-agent.service"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "root";
        };
        script = ''
          set -euo pipefail
          dst=/var/lib/nixfleet/bootstrap-token
          if [ -f /var/lib/nixfleet/agent-cert.pem ]; then
            rm -f "$dst"
            exit 0
          fi
          mkdir -p /var/lib/nixfleet
          cp /etc/nixfleet-demo/bootstrap-token.json "$dst"
          chmod 0600 "$dst"
        '';
      };

      services.nginx = {
        enable = true;
        virtualHosts.default = {default = true;};
      };

      networking.firewall.allowedTCPPorts = [80];

      compliance.frameworks.nis2 = {
        enable = true;
        entityType = "essential";
      };
      compliance.governance.hostType = "server";
    }
  ];
}
