# web-02: edge-channel web agent.
#
# Identical to web-01 except for hostName. Channel assignment (`channel = "edge"`)
# lives in fleet.nix.
#
# /version returns "1.0.0\n" via modules/web-version.nix (shared with web-01).
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
        # Per-host health probes (nixfleet #86). See web-01.nix for
        # the rationale; identical config so both web hosts gate on
        # the same /version contract.
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
