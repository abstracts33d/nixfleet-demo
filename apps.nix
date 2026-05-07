# Bootstrap apps for the v0.2 demo.
#
#   nix run .#start-vm -- -h <host>      — boot a VM
#   nix run .#start-vm -- --all          — boot every VM
#   nix run .#stop-vm  -- -h <host>      — stop a VM
#   nix run .#clean-vm -- -h <host>      — wipe per-host VM state
#   nix run .#build-vm -- -h <host>      — rebuild a host's qcow2 disk
#   nix run .#fetch-release-key          — phase 1: copy forge's ed25519
#                                          pubkey into modules/trust.nix
#   nix run .#push-repo                  — push the local repo to forge
#
# SSH host ports (mkVmApps default, alphabetical 2201+idx):
#   cp    -> 2201
#   forge -> 2202
#   web-01   -> 2203
#   web-02   -> 2204
#
# Additional service ports declared via hostSpec.vmPortForwards (#87):
#   forge: 2222 -> 222 (Forgejo SSH), 3001 -> 3001 (HTTP), 8081 -> 8081 (Attic)
#   cp:    8443 -> 8443 (control plane TLS)
#   web-01:   2280 -> 80   (nginx)
#   web-02:   2281 -> 80   (nginx)
{inputs, ...}: {
  perSystem = {pkgs, ...}: let
    vmApps = inputs.nixfleet.lib.mkVmApps {inherit pkgs;};

    fetchReleaseKey = pkgs.writeShellApplication {
      name = "fetch-release-key";
      runtimeInputs = [pkgs.openssh pkgs.coreutils pkgs.gnused pkgs.git pkgs.gawk];
      text = ''
        set -euo pipefail
        repo_root="$(git rev-parse --show-toplevel)"
        trust_file="$repo_root/modules/trust.nix"
        marker='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
        if ! grep -q "$marker" "$trust_file"; then
          echo "trust.nix already has a fetched key, nothing to do."
          exit 0
        fi
        echo "Note: forge must already be running. Run:"
        echo "      nix run .#start-vm -- -h forge"
        echo "Polling forge:2202 (SSH) for /var/lib/nixfleet-release/key.pub..."
        pubkey=""
        for _ in $(seq 1 60); do
          if pubkey=$(ssh -p 2202 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                          -i "$repo_root/secrets/demo-ssh-key" \
                          -o ConnectTimeout=2 \
                          root@localhost \
                          cat /var/lib/nixfleet-release/key.pub 2>/dev/null); then
            break
          fi
          sleep 1
        done
        if [ -z "$pubkey" ]; then
          echo "forge did not surface /var/lib/nixfleet-release/key.pub within 60s." >&2
          echo "Hint: ssh -p 2202 root@localhost journalctl -u nixfleet-release-keygen" >&2
          exit 1
        fi
        b64=$(echo "$pubkey" | awk '{print $2}')
        sed -i "s|public = \"$marker\";|public = \"$b64\";|" "$trust_file"
        ( cd "$repo_root" && git add modules/trust.nix \
          && git commit -m "chore(demo): fetch release-signing pubkey from forge" )
        echo "Trust file updated. Now run \`nix run .#start-vm -- --all\` and \`nix run .#push-repo\`."
      '';
    };

    pushRepo = pkgs.writeShellApplication {
      name = "push-repo";
      runtimeInputs = [pkgs.git pkgs.openssh];
      text = ''
        set -euo pipefail
        repo_root="$(git rev-parse --show-toplevel)"
        ssh_key="$repo_root/secrets/demo-ssh-key"
        # forge host port-forward 2222 -> guest:222 (Forgejo SSH)
        # via hostSpec.vmPortForwards. Direct push, no tunnel needed.
        export GIT_SSH_COMMAND="ssh -p 2222 -i $ssh_key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
        # Probe Forgejo SSH with a real git command — `ssh ... true` always
        # exits 1 because Forgejo SSH only handles git protocol commands.
        if ! git ls-remote "git@localhost:demo/fleet.git" HEAD >/dev/null 2>&1; then
          echo "forge Forgejo SSH not reachable on 2222 — run \`nix run .#start-vm -- -h forge\` first." >&2
          echo "If forge is up, the admin user / key / repo bootstrap may not be done yet." >&2
          echo "Watch: ssh -p 2202 root@localhost 'systemctl status forgejo-ssh-keys forgejo-repositories'" >&2
          exit 1
        fi
        ( cd "$repo_root" && git push --force "git@localhost:demo/fleet.git" HEAD:main )
      '';
    };
  in {
    apps =
      vmApps
      // {
        fetch-release-key = {
          type = "app";
          program = "${fetchReleaseKey}/bin/fetch-release-key";
          meta.description = "Phase 1 trust bootstrap: copy forge's ed25519 release pubkey into modules/trust.nix";
        };
        push-repo = {
          type = "app";
          program = "${pushRepo}/bin/push-repo";
          meta.description = "Push the local repo to forge's Forgejo via host:2222 -> guest:222";
        };
      };
  };
}
