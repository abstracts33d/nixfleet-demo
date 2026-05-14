# web-02: edge-channel web agent.
#
# Identical to web-01 except for hostName + channel. See web-01.nix for
# the path A trust-delivery rationale.
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
        tls.caCert = "/var/lib/nixfleet-demo/fleet-ca.pem";
        tls.clientKey = "/var/lib/nixfleet-demo/agent-client.key";
        bootstrapTokenFile = "/var/lib/nixfleet-demo/bootstrap-token.json";
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

      systemd.services.nixfleet-agent.unitConfig.ConditionPathExists = "/var/lib/nixfleet-demo/agent-client.key";

      # See web-01.nix -- guarantee /var/lib/nixfleet exists before
      # the agent writes its first-issued cert there.
      systemd.tmpfiles.rules = [
        "d /var/lib/nixfleet 0700 root root - -"
      ];

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

      nixfleet.persistence.directories = ["/var/lib/nixfleet-demo"];
    }
  ];
}
