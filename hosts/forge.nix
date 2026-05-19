# forge: Forgejo + harmonia binary cache + Forgejo Actions runner + release-signer.
#
# Exposes:
#   - HTTP Forgejo on :3001          (-> host :3001)
#   - Forgejo SSH on :222            (-> host :2222, used by `nix run .#push-repo`)
#   - harmonia binary cache on :5000 (-> host :5000)
#   - System SSH on :22              (-> host :2200)
#
# Bootstrap order:
#   1. First boot generates an ed25519 release-signing key under
#      /var/lib/nixfleet-release/. Agents pull closures from harmonia,
#      which serves /nix/store with signatures from the cache-signing-key
#      staged by `provision-secrets`.
#   2. `nix run .#fetch-release-key` reads /var/lib/nixfleet-release/key.pub over
#      SSH and writes it into modules/trust.nix.
#   3. `nix run .#push-repo` pushes the demo repo to git@localhost:2222/demo/fleet.git.
#   4. Forgejo Actions picks up the push, runs CI (.forgejo/workflows/ci.yml),
#      signs fleet.resolved.json with the ed25519 key, commits the signature back.
{
  inputs,
  self,
  ...
}:
inputs.nixfleet.lib.mkHost {
  hostName = "forge";
  platform = "x86_64-linux";
  # forge is intentionally NOT a fleet member (see fleet.nix), so the
  # framework's `mkFleet → nixosConfigurations` auto-wiring does not
  # cover it. This file documents the manual-mkHost path for any host
  # that operates outside `mkFleet { hosts.<n>.nixosArgs = {...} }` —
  # the same wiring the framework wrapper applies internally. Fleet
  # members in this demo (cp, web-{01,02}) go through the auto-wired
  # path; only forge is operator-built.
  #
  # `effectiveHealthChecks.forge` is absent from the resolver output
  # (forge isn't in fleet.hosts), so `or {}` short-circuits to `{}`
  # in mk-host.nix:65 — forge gets no probes, matching its
  # trust-anchor-outside-the-fleet role.
  fleetResolved = self.fleet.resolved;
  isVm = true;
  hostSpec = {
    userName = "root";
    timeZone = "UTC";
    locale = "en_US.UTF-8";
    vmPortForwards = {
      "222" = 2222; # Forgejo SSH (host:2222 -> guest:222)
      "3001" = 3001; # Forgejo HTTP
      "5000" = 5000; # harmonia binary cache
    };
    # In-VM CI compiles the nixfleet Rust workspace (nixfleet-release).
    # 1024 MiB OOM-thrashes during `nix flake metadata` + cargo build.
    vmRam = 4096;
  };
  modules = [
    ./_shared/qemu-vm.nix
    ../modules/trust.nix

    ../modules/fleet-version.nix

    ../modules/demo-cache.nix
    ../modules/scopes/coordinator
    inputs.nixfleet.scopes.persistence.impermanence
    (
      {pkgs, ...}: {
        nixfleet.coordinator = {
          enable = true;
          domain = "demo.invalid";
        };

        nixfleet.forge = {
          domain = "forge.demo.invalid";
          appName = "Nixfleet Demo Forge";
          # Bind on all interfaces so peer VMs can reach Forgejo HTTP via
          # the multicast VLAN (`forge:3001` from cp's POV resolves to
          # 10.0.100.2 - see modules/vm-network.nix). Production puts a
          # reverse proxy in front and keeps Forgejo on loopback.
          http.addr = "0.0.0.0";
          ssh.openFirewall = true;
          # First-boot admin user `demo` and SSH key `secrets/demo-ssh-key.pub`
          # registered against it. push-repo authenticates as `git@localhost`,
          # Forgejo matches the offered key against demo's registered keys.
          admin.userFile = "/etc/nixfleet-demo/forgejo-admin-creds";
          admin.sshKeyFiles = ["/etc/nixfleet-demo/forgejo-admin.pub"];
          repositories = [
            {
              owner = "demo";
              name = "fleet";
              description = "Demo fleet config";
            }
          ];
        };

        # Demo admin credentials and SSH pubkey baked into /etc.
        # PUBLIC, NOT FOR PRODUCTION - see secrets/README.md.
        environment.etc."nixfleet-demo/forgejo-admin-creds" = {
          text = "demo:demo@nixfleet-demo.invalid:demoadmin1!\n";
          mode = "0640";
          user = "forgejo";
          group = "forgejo";
        };
        environment.etc."nixfleet-demo/forgejo-admin.pub".source =
          ../secrets/demo-ssh-key.pub;

        nixfleet.ciRunner.forgejoActions = {
          instanceUrl = "http://localhost:3001";
          registrationTokenFile = "/var/lib/forgejo/runner-token";
          name = "forge-native";
        };

        nixfleet.releaseSigner.enable = true;

        # First-boot oneshot: mint a Forgejo runner registration token.
        # NixOS forgejo writes app.ini at /var/lib/forgejo/custom/conf/app.ini
        # (FORGEJO_CUSTOM env var). The token is a 40-char hex string;
        # we validate the output before writing so a bootstrap-with-no-config
        # error doesn't poison the file and survive reboots.
        systemd.services.forgejo-runner-token-bootstrap = {
          description = "Mint Forgejo runner registration token on first boot";
          wantedBy = ["multi-user.target"];
          after = ["forgejo.service"];
          requires = ["forgejo.service"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "forgejo";
            Group = "forgejo";
            Environment = "FORGEJO_CUSTOM=/var/lib/forgejo/custom FORGEJO_WORK_DIR=/var/lib/forgejo";
          };
          script = ''
            set -euo pipefail
            token_file=/var/lib/forgejo/runner-token
            # The NixOS gitea-actions-runner module wires this file as
            # `EnvironmentFile=` for the runner unit, so the file must be in
            # KEY=VALUE form. The expected variable is TOKEN, consumed by
            # the register-runner pre-start script.
            # Regenerate if missing or not in TOKEN=<40-char> form.
            if [ ! -s "$token_file" ] || ! grep -qE '^TOKEN=[A-Za-z0-9]{40,}$' "$token_file"; then
              token=$(${pkgs.forgejo}/bin/forgejo actions generate-runner-token \
                -c /var/lib/forgejo/custom/conf/app.ini)
              if [ -z "$token" ] || ! echo "$token" | grep -qE '^[A-Za-z0-9]{40,}$'; then
                echo "forgejo emitted invalid runner token: $token" >&2
                exit 1
              fi
              umask 077
              printf 'TOKEN=%s\n' "$token" > "$token_file"
              # 0644 - gitea-runner (different user from forgejo) reads
              # this via EnvironmentFile at registration time.
              chmod 0644 "$token_file"
            fi
          '';
        };

        # Runner registration reads /var/lib/forgejo/runner-token at start.
        # Without an explicit ordering it can race the bootstrap oneshot
        # (both depend only on forgejo.service) and exit with "token is empty".
        systemd.services.gitea-runner-nixfleet = {
          after = ["forgejo-runner-token-bootstrap.service"];
          requires = ["forgejo-runner-token-bootstrap.service"];
        };

        # Persist runner token + Forgejo data + release-signer key across
        # reboots. Without these entries, impermanence wipes the root and
        # the demo loses its identity on every boot.
        nixfleet.persistence.files = [
          "/var/lib/forgejo/runner-token"
        ];
        nixfleet.persistence.directories = [
          "/var/lib/forgejo"
          "/var/lib/nixfleet-release"
          "/var/lib/nixfleet-demo"
        ];

        # forge does NOT run nixfleet-agent. It is the trust anchor
        # (signs releases) + CI runner + binary cache -- outside the
        # fleet it serves, like build farms in real deployments. Including
        # forge as a fleet member would create a chicken-and-egg where
        # forge's own closure bakes a trust pin that doesn't match the
        # release key forge regenerated on its last install.

        # forge carries more services than the others. Resource sizing
        # (memory, disk) for the QEMU runner is handled by mkVmApps in
        # apps.nix, NOT here - the `virtualisation.*` options aren't
        # registered when evaluating system.build.toplevel.

        # Open the Forgejo HTTP port for the in-VM CI workflow + the host
        # port-forward exposed by mkVmApps.
        networking.firewall.allowedTCPPorts = [3001];
      }
    )
  ];
}
