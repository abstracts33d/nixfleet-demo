# cp: nixfleet control plane.
#
# Polls forge's git for fleet.resolved.json + signature. Validates against
# the ed25519 pubkey declared in modules/trust.nix. Dispatches rollout actions
# to agents per channel/wave/edge policies declared in fleet.nix.
#
# Compliance: NIS2 essential (the demo's compliance posture demonstration).
#
# Path A trust delivery (private material): cp does NOT bake the fleet
# CA private key or the operator mTLS key into its closure. The operator
# runs `nix run .#provision-secrets -- -h cp` AFTER first boot to scp
# the keys into /var/lib/nixfleet-demo/. The TLS keygen oneshot and the
# control-plane service are gated by ConditionPathExists on the fleet CA
# key -- without it they stay inert (no crash-loop), and `provision-secrets`
# starts them after staging the material.
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

          # Agent cert CN suffix. Demo CA has no dNSName constraint
          # so any string works; production fleets must match this to
          # the issuance CA's dNSName extension (nixfleet D14).
          agentCnSuffix = "fleet.demo";

          tls.cert = "/var/lib/nixfleet-control-plane/tls/cert.pem";
          tls.key = "/var/lib/nixfleet-control-plane/tls/key.pem";
          # Same CA root for both directions: agents present certs
          # signed by the fleet CA at /v1/agent/*; operators present
          # certs signed by the same CA at /v1/hosts. Without this,
          # CP runs TLS-only and 401s every /v1/* request.
          tls.clientCa = "/var/lib/nixfleet-demo/fleet-ca.pem";

          # Issuance CA: signs agent client certs at /v1/enroll and
          # /v1/agent/renew. Demo: file-based (FileCaSigner). Production:
          # tpmCaPubkeyRaw + tpmCaSignWrapper -- keeps the CA private
          # half inside the TPM and survives disk loss.
          fleetCaCert = "/var/lib/nixfleet-demo/fleet-ca.pem";
          fleetCaKey = "/var/lib/nixfleet-demo/fleet-ca-key.pem";

          # Poll forge's Forgejo HTTP. Inter-VM hostname resolution is
          # via the multicast VLAN configured by `start-vm --vlan 1234`
          # + the static-IP/extraHosts wiring in modules/vm-network.nix.
          channelRefsSource = {
            artifactUrl = "http://forge:3001/demo/fleet/raw/branch/main/releases/fleet.resolved.json";
            signatureUrl = "http://forge:3001/demo/fleet/raw/branch/main/releases/fleet.resolved.json.sig";
          };

          # Empty list is a steady state for the demo. CP still verifies the
          # (empty) signed revocations artifact -- exercises gap C.
          revocationsSource = {
            artifactUrl = "http://forge:3001/demo/fleet/raw/branch/main/releases/revocations.json";
            signatureUrl = "http://forge:3001/demo/fleet/raw/branch/main/releases/revocations.json.sig";
          };
        };

        # CLI defaults: NIXFLEET_* env vars so `nixfleet status` resolves
        # its mTLS config without `nixfleet config init`. URL uses `cp`
        # (resolves to 10.0.100.1 via vm-network.nix) -- the cert SAN
        # also covers `localhost`/`127.0.0.1` for parity with mkVmApps'
        # host port-forward (host:8443 -> guest:8443).
        environment.variables = {
          NIXFLEET_CP_URL = "https://cp:8443";
          NIXFLEET_CA_CERT = "/var/lib/nixfleet-demo/fleet-ca.pem";
          NIXFLEET_CLIENT_CERT = "/var/lib/nixfleet-demo/operator.pem";
          NIXFLEET_CLIENT_KEY = "/var/lib/nixfleet-demo/operator.key";
        };

        # Gate both the TLS keygen oneshot and the control-plane service
        # on the fleet CA key existing. Without provisioning, the daemon
        # stays inert (no crash-loop logging "file not found" every second).
        # `nix run .#provision-secrets -- -h cp` lands the file and then
        # starts the units explicitly.
        systemd.services.nixfleet-control-plane.unitConfig.ConditionPathExists = "/var/lib/nixfleet-demo/fleet-ca-key.pem";

        # First-boot oneshot: sign the CP TLS server cert using the
        # provisioned fleet CA. SAN list: `cp` + `cp.demo.invalid` for
        # VLAN peers, 127.0.0.1 + 10.0.100.1 for local probes and the
        # host port-forward (mkVmApps maps 8443 -> guest:8443),
        # localhost for completeness.
        systemd.services.nixfleet-cp-tls-keygen = {
          description = "First-boot CP TLS server cert (signed by fleet CA)";
          wantedBy = ["multi-user.target"];
          before = ["nixfleet-control-plane.service"];
          unitConfig.ConditionPathExists = "/var/lib/nixfleet-demo/fleet-ca-key.pem";
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
            csr="$tls_dir/cp.csr"
            if [ -f "$cert" ] && [ -f "$key" ]; then
              exit 0
            fi
            ${pkgs.openssl}/bin/openssl genpkey -algorithm ed25519 -out "$key"
            chmod 0600 "$key"
            ${pkgs.openssl}/bin/openssl req -new -key "$key" -out "$csr" \
              -subj "/CN=cp.demo.invalid"
            cat > "$tls_dir/cp.ext" <<EOF
            subjectAltName=DNS:cp,DNS:cp.demo.invalid,DNS:localhost,IP:127.0.0.1,IP:10.0.100.1
            extendedKeyUsage=serverAuth
            EOF
            ${pkgs.openssl}/bin/openssl x509 -req \
              -in "$csr" \
              -CA /var/lib/nixfleet-demo/fleet-ca.pem \
              -CAkey /var/lib/nixfleet-demo/fleet-ca-key.pem \
              -CAcreateserial \
              -out "$cert" \
              -days 3650 \
              -extfile "$tls_dir/cp.ext"
            chmod 0644 "$cert"
            rm -f "$csr" "$tls_dir/cp.ext"
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

        # /var/lib/nixfleet-demo persists the operator-provisioned
        # private material across reboots (impermanence wipes /).
        nixfleet.persistence.directories = [
          "/var/lib/nixfleet-control-plane"
          "/var/lib/nixfleet-compliance"
          "/var/lib/nixfleet-demo"
        ];
      }
    )
  ];
}
