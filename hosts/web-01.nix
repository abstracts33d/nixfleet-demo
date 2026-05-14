# web-01: stable-channel web agent.
#
# Channel assignment lives in fleet.nix (`hosts.web-01.channel = "stable"`).
# This file declares the host's NixOS config; the channel decision is the
# fleet topology's job.
#
# /version returns "1.0.0\n" via modules/web-version.nix (shared with web-02).
# Bumping the version string in that file changes both web closures; the
# rollout sequence is gated by fleet.nix's channelEdges + canary policy.
#
# Path A trust delivery:
#   1. fleet.nix declares this host's mTLS client pubkey by reading
#      ../secrets/host-keys/web-01.pub (PUBLIC, tracked in git).
#   2. The matching private key + fleet CA cert + bootstrap token are
#      scp'd into /var/lib/nixfleet-demo/ by `nix run .#provision-secrets`
#      AFTER first boot. Not baked into the closure.
#   3. The agent service is gated by ConditionPathExists on the client
#      key -- it waits inert until provisioning, then provision-secrets
#      starts it explicitly.
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
        # Agent verifies CP's TLS server cert against this CA.
        tls.caCert = "/var/lib/nixfleet-demo/fleet-ca.pem";
        # Dedicated agent identity key (NOT the SSH host key). The
        # matching pubkey is declared in fleet.nix; CP rejects any
        # CSR whose pubkey doesn't match the fleet declaration.
        tls.clientKey = "/var/lib/nixfleet-demo/agent-client.key";
        # One-shot bootstrap token (signed by org root key, 168h
        # validity). Agent reads it on first enrollment, ignores it
        # thereafter (cert at /var/lib/nixfleet/agent-cert.pem takes
        # precedence).
        bootstrapTokenFile = "/var/lib/nixfleet-demo/bootstrap-token.json";
        # Per-host health probes (nixfleet #86). The agent runs each
        # probe on its own interval; the reconciler gates Healthy ->
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

      # Gate the agent on the operator-supplied private key. Without
      # this, the unit crash-loops every second logging "file not found"
      # until provisioning lands. With it, the unit is inert until
      # provision-secrets stages the key and starts it explicitly.
      systemd.services.nixfleet-agent.unitConfig.ConditionPathExists = "/var/lib/nixfleet-demo/agent-client.key";

      # Ensure /var/lib/nixfleet exists before the agent runs. The
      # agent module declares it in `nixfleet.persistence.directories`
      # but impermanence's bind-mount source isn't pre-created -- the
      # agent's first-run atomic-write of `agent-cert.pem` fails with
      # ENOENT otherwise. Worth filing upstream as a framework bug.
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

      # /var/lib/nixfleet-demo persists the operator-provisioned
      # private material across reboots (impermanence wipes /).
      nixfleet.persistence.directories = ["/var/lib/nixfleet-demo"];
    }
  ];
}
