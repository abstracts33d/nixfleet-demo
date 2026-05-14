# Bootstrap apps for the v0.2 demo.
#
#   nix run .#start-vm -- -h <host>      -- boot a VM
#   nix run .#start-vm -- --all          -- boot every VM
#   nix run .#stop-vm  -- -h <host>      -- stop a VM
#   nix run .#clean-vm -- -h <host>      -- wipe per-host VM state
#   nix run .#build-vm -- -h <host>      -- rebuild a host's qcow2 disk
#   nix run .#fetch-release-key          -- phase 1: copy forge's ed25519
#                                          pubkey into modules/trust.nix
#   nix run .#provision-secrets -- --all -- scp operator-private material
#                                          into each VM's /var/lib/nixfleet-demo
#                                          (gated services start after this)
#   nix run .#push-repo                  -- push the local repo to forge
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
        placeholder='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
        echo "Note: forge must already be running. Run:"
        echo "      nix run .#start-vm -- -h forge --vlan 1234"
        echo "Polling forge:2202 (SSH) for /var/lib/nixfleet-release/key.pub.b64..."
        b64=""
        for _ in $(seq 1 60); do
          # key.pub.b64 contains the raw 32-byte ed25519 pubkey, base64-encoded
          # (the trust.json wire format). The release-signer scope generates
          # this alongside the PEM private key on first boot.
          if b64=$(ssh -p 2202 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                       -i "$repo_root/secrets/demo-ssh-key" \
                       -o ConnectTimeout=2 \
                       root@localhost \
                       cat /var/lib/nixfleet-release/key.pub.b64 2>/dev/null); then
            break
          fi
          sleep 1
        done
        if [ -z "$b64" ]; then
          echo "forge did not surface /var/lib/nixfleet-release/key.pub.b64 within 60s." >&2
          echo "Hint: ssh -p 2202 root@localhost journalctl -u nixfleet-release-keygen" >&2
          exit 1
        fi
        # Find the current public-key line in trust.nix (placeholder or
        # previously-fetched). Idempotent: if forge's key matches what
        # the file already holds, exit clean without a churn commit.
        current=$(grep -oE 'public = "[^"]+";' "$trust_file" | head -1 | sed -E 's/public = "([^"]+)";/\1/')
        if [ "$current" = "$b64" ]; then
          echo "trust.nix already pinned to forge's current pubkey -- no change."
          exit 0
        fi
        sed -i -E "s|public = \"[^\"]+\";|public = \"$b64\";|" "$trust_file"
        if [ "$current" = "$placeholder" ]; then
          msg="chore(demo): fetch release-signing pubkey from forge"
        else
          msg="chore(demo): refresh release-signing pubkey from forge (rotation)"
        fi
        ( cd "$repo_root" && git add modules/trust.nix && git commit -m "$msg" )
        echo "Trust file updated. Now run \`nix run .#start-vm -- --all --vlan 1234\` and \`nix run .#push-repo\`."
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
        # Probe Forgejo SSH with a real git command -- `ssh ... true` always
        # exits 1 because Forgejo SSH only handles git protocol commands.
        if ! git ls-remote "git@localhost:demo/fleet.git" HEAD >/dev/null 2>&1; then
          echo "forge Forgejo SSH not reachable on 2222 -- run \`nix run .#start-vm -- -h forge\` first." >&2
          echo "If forge is up, the admin user / key / repo bootstrap may not be done yet." >&2
          echo "Watch: ssh -p 2202 root@localhost 'systemctl status forgejo-ssh-keys forgejo-repositories'" >&2
          exit 1
        fi
        ( cd "$repo_root" && git push --force "git@localhost:demo/fleet.git" HEAD:main )
      '';
    };

    # Path A trust delivery: scp the operator-private demo material
    # into each running VM's /var/lib/nixfleet-demo/. The host modules
    # reference these paths without `builtins.readFile`, so private
    # keys never enter the flake source tree (gitignored under
    # secrets/). Services on cp + web hosts are gated by
    # ConditionPathExists on the provisioned files; this script
    # starts them after staging.
    #
    # Host SSH ports (mkVmApps auto-assignment, alphabetical 2201+idx):
    #   cp=2201, forge=2202, web-01=2203, web-02=2204
    provisionSecrets = pkgs.writeShellApplication {
      name = "provision-secrets";
      runtimeInputs = [pkgs.openssh pkgs.coreutils];
      text = ''
        set -euo pipefail
        repo_root="$(git rev-parse --show-toplevel)"
        ssh_key="$repo_root/secrets/demo-ssh-key"
        ssh_opts=(-i "$ssh_key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

        host=""
        all=0
        while [ $# -gt 0 ]; do
          case "$1" in
            -h|--host) host="$2"; shift 2 ;;
            --all)     all=1; shift ;;
            -*)        echo "Unknown flag: $1" >&2; exit 2 ;;
            *)         echo "Unexpected argument: $1" >&2; exit 2 ;;
          esac
        done

        if [ "$all" = 0 ] && [ -z "$host" ]; then
          echo "Usage: nix run .#provision-secrets -- -h HOST" >&2
          echo "       nix run .#provision-secrets -- --all" >&2
          echo "" >&2
          echo "Hosts: cp web-01 web-02 (forge has no private material to provision)" >&2
          exit 2
        fi

        ssh_port_for() {
          case "$1" in
            cp)     echo 2201 ;;
            forge)  echo 2202 ;;
            web-01) echo 2203 ;;
            web-02) echo 2204 ;;
            *)      echo "unknown host: $1" >&2; return 1 ;;
          esac
        }

        wait_for_ssh() {
          local h="$1" port
          port=$(ssh_port_for "$h")
          for _ in $(seq 1 30); do
            if ssh "''${ssh_opts[@]}" -p "$port" -o ConnectTimeout=2 \
                 root@localhost true 2>/dev/null; then
              return 0
            fi
            sleep 2
          done
          echo "$h: SSH on port $port not reachable after 60s." >&2
          echo "Run \`nix run .#start-vm -- -h $h --vlan 1234\` first." >&2
          return 1
        }

        provision_cp() {
          local port; port=$(ssh_port_for cp)
          echo "==> cp: staging fleet CA + operator cert"
          wait_for_ssh cp
          # Stage to a tmpfile via stdin so we don't need scp; then
          # atomic-move into place + chmod. Avoids leaving the
          # private key at a permissive mode mid-copy.
          stage() {
            local src="$1" dst="$2" mode="$3"
            ssh "''${ssh_opts[@]}" -p "$port" root@localhost \
              "mkdir -p /var/lib/nixfleet-demo && install -m $mode /dev/stdin $dst" \
              < "$src"
          }
          stage "$repo_root/secrets/fleet-ca.pem"     /var/lib/nixfleet-demo/fleet-ca.pem     0644
          stage "$repo_root/secrets/fleet-ca-key.pem" /var/lib/nixfleet-demo/fleet-ca-key.pem 0600
          stage "$repo_root/secrets/operator.pem"     /var/lib/nixfleet-demo/operator.pem     0644
          stage "$repo_root/secrets/operator.key"     /var/lib/nixfleet-demo/operator.key     0600
          echo "==> cp: starting gated services"
          ssh "''${ssh_opts[@]}" -p "$port" root@localhost \
            "systemctl start nixfleet-cp-tls-keygen && systemctl restart nixfleet-control-plane"
          echo "    cp: provisioning complete."
        }

        provision_web() {
          local h="$1" port
          port=$(ssh_port_for "$h")
          echo "==> $h: staging fleet CA + agent identity + bootstrap token"
          wait_for_ssh "$h"
          stage() {
            local src="$1" dst="$2" mode="$3"
            ssh "''${ssh_opts[@]}" -p "$port" root@localhost \
              "mkdir -p /var/lib/nixfleet-demo && install -m $mode /dev/stdin $dst" \
              < "$src"
          }
          stage "$repo_root/secrets/fleet-ca.pem"                  /var/lib/nixfleet-demo/fleet-ca.pem        0644
          stage "$repo_root/secrets/host-keys/$h"                  /var/lib/nixfleet-demo/agent-client.key    0600
          stage "$repo_root/secrets/bootstrap-tokens/$h.json"      /var/lib/nixfleet-demo/bootstrap-token.json 0600
          echo "==> $h: starting nixfleet-agent"
          ssh "''${ssh_opts[@]}" -p "$port" root@localhost \
            "systemctl restart nixfleet-agent"
          echo "    $h: provisioning complete."
        }

        if [ "$all" = 1 ]; then
          provision_cp
          provision_web web-01
          provision_web web-02
        else
          case "$host" in
            cp)             provision_cp ;;
            web-01|web-02)  provision_web "$host" ;;
            forge)          echo "forge has no operator-private material to provision; skipping." ;;
            *)              echo "unknown host: $host" >&2; exit 2 ;;
          esac
        fi
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
        provision-secrets = {
          type = "app";
          program = "${provisionSecrets}/bin/provision-secrets";
          meta.description = "Stage operator-private demo material (fleet CA key, agent key, operator key, bootstrap tokens) into each running VM's /var/lib/nixfleet-demo and start gated services.";
        };
      };
  };
}
