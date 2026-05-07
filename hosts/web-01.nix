# web-01: stable-channel web agent.
#
# Channel assignment lives in fleet.nix (`hosts.web-01.channel = "stable"`).
# This file declares the host's NixOS config; the channel decision is the
# fleet topology's job.
#
# /version returns "1.0.0\n" via modules/web-version.nix (shared with web-02).
# Bumping the version string in that file changes both web closures; the
# rollout sequence is gated by fleet.nix's channelEdges + canary policy.
{inputs, ...}:
inputs.nixfleet.lib.mkHost {
  hostName = "web-01";
  platform = "x86_64-linux";
  isVm = true;
  hostSpec = {
    userName = "root";
    timeZone = "UTC";
    locale = "en_US.UTF-8";
    vmPortForwards = {
      "80" = 2280; # nginx
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
        # Per-host health probes (nixfleet #86). The agent runs each
        # probe on its own interval; the reconciler gates Healthy →
        # Soaked promotion on `all-probes-passing`. A failing probe
        # holds the wave at this step (mode = enforce).
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
