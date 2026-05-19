# Apps for the v0.2 demo.
#
#   nix run .                            -- single-host compliance demo (default,
#                                          ~2-5 min, signed NIS2 evidence)
#   nix run .#fleet                      -- print the 4-VM walkthrough hints
#   nix run .#start-vm -- -h <host>      -- boot a VM
#   nix run .#start-vm -- --all          -- boot every VM
#   nix run .#stop-vm  -- -h <host>      -- stop a VM
#   nix run .#clean-vm -- -h <host>      -- wipe per-host VM state
#   nix run .#build-vm -- -h <host>      -- rebuild a host's qcow2 disk
#   nix run .#fetch-release-key          -- phase 1: copy forge's ed25519
#                                          pubkey into modules/trust.nix
#   nix run .#push-repo                  - push the local repo to forge
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

    # Bastion VM derivation, evaluated locally so it stays out of
    # flake.nixosConfigurations (which would shift mkVmApps' alphabetical
    # SSH port assignment). Exposed below as packages.bastion-vm so the
    # default app can `nix build` it by path.
    bastion = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        inputs.compliance.nixosModules.nis2
        ./compliance-only/bastion.nix
      ];
    };

    # Default `nix run` target: the single-host compliance demo. One NixOS
    # host, NIS2-essential preset, no fleet, no agent, no control plane.
    # Boots to a root shell in ~2-5 min; user runs `compliance-check` and
    # sees signed evidence. This is the credible "click-and-see" demo.
    runBastion = pkgs.writeShellApplication {
      name = "nixfleet-demo";
      runtimeInputs = [pkgs.nix pkgs.coreutils];
      text = ''
                set -euo pipefail

                # Preflight: KVM. The bastion is a qemu-vm; without /dev/kvm it
                # technically still boots under TCG but is unusably slow. Refuse
                # rather than letting the user think the demo is hung.
                if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
                  cat >&2 <<'EOF'
        ERROR: /dev/kvm is not accessible.

        The demo boots a Linux VM and needs hardware virtualisation.

        Fixes:
          - Add yourself to the kvm group:
              sudo usermod -aG kvm "$USER" && newgrp kvm
          - Confirm CPU virt is enabled in BIOS/UEFI:
              grep -E '(vmx|svm)' /proc/cpuinfo
          - On macOS: this demo needs Linux (see docs/macos.md).
        EOF
                  exit 1
                fi

                # Preflight: free disk in the Nix store. 4 GiB is enough for the
                # bastion closure on a cold store; warn rather than refuse so a
                # user with shared store doesn't get blocked unnecessarily.
                need_gb=4
                avail_kb=$(df -k /nix/store 2>/dev/null | awk 'NR==2 {print $4}')
                if [ -n "''${avail_kb:-}" ]; then
                  avail_gb=$(( avail_kb / 1024 / 1024 ))
                  if [ "$avail_gb" -lt "$need_gb" ]; then
                    echo "WARN: only ''${avail_gb} GB free in /nix/store (recommend >= ''${need_gb} GB)." >&2
                  fi
                fi

                echo
                echo "nixfleet-compliance demo: one NixOS host, NIS2-essential, signed evidence."
                echo
                echo "Building the VM (cold cache: a few minutes; warm: seconds)..."
                nix build --print-build-logs \
                  --out-link /tmp/nixfleet-demo-bastion \
                  "${inputs.self}#packages.x86_64-linux.bastion-vm"
                echo
                echo "Booting. Console login is automatic; you land at a root prompt."
                echo "Once at the shell:"
                echo "  compliance-check         # latest signed evidence + verification"
                echo "  compliance-check --help  # full CLI"
                echo "  cat /var/lib/nixfleet-compliance/evidence.json | jq ."
                echo
                echo "To exit the VM: press Ctrl-A, then x (release Ctrl-A first), twice."
                echo
                # The qemu-vm module names the runner run-<hostname>-vm. Hostname
                # is "bastion" (see compliance-only/bastion.nix). Defensive glob
                # in case nixpkgs changes the convention.
                exec /tmp/nixfleet-demo-bastion/bin/run-*-vm
      '';
    };

    # `nix run .#fleet` is intentionally NOT a launcher. The 4-VM
    # walkthrough is 10 steps and takes 45-90 min on a cold cache; we
    # don't try to compress it into a one-shot. Instead, print the path
    # so the user knows where to go and what to run next. Same surface
    # as `nix run .` failing today, but with an actionable message.
    fleetInfo = pkgs.writeShellApplication {
      name = "nixfleet-demo-fleet";
      runtimeInputs = [];
      text = ''
                cat <<'EOF'
        The 4-VM reference fleet (forge + control plane + two agents)
        demonstrates the full signed-GitOps loop end-to-end. First run
        takes 45-90 min (cold nixpkgs + Rust compile on the CI VM).

        For a 2-5 min single-host demo with signed compliance evidence:
          nix run github:arcanesys/nixfleet-demo

        To run the full 4-VM fleet, follow the README walkthrough:

          1. bash secrets/regenerate-demo-identity.sh
          2. nix run .#build-vm -- --all --identity-key secrets/demo-ssh-key
          3. nix run .#start-vm -- -h forge --vlan 1234
             nix run .#fetch-release-key
          4. nix run .#start-vm -- -h cp     --vlan 1234
             nix run .#start-vm -- -h web-01 --vlan 1234
             nix run .#start-vm -- -h web-02 --vlan 1234
          5. nix run .#provision-secrets -- --all
          6. nix run .#push-repo
          7. ssh -p 2201 root@localhost nixfleet status

        Full walkthrough + troubleshooting:
          https://github.com/arcanesys/nixfleet-demo#full-reference-fleet-4-vm-walkthrough
        EOF
      '';
    };

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
        # 180 attempts at 1s each = 3 min wall clock. Cold first-boot can
        # take 60-120s while forgejo's repo init + nix-store optimization
        # run before the release-keygen oneshot. 60s was too aggressive.
        for i in $(seq 1 180); do
          # IdentityAgent=none so a polluted operator agent (yubikey + work
          # keys + ...) can't hit MaxAuthTries on the freshly-installed
          # forge sshd. -i is the only key we offer.
          if b64=$(ssh -p 2202 \
                       -o IdentityAgent=none \
                       -o StrictHostKeyChecking=no \
                       -o UserKnownHostsFile=/dev/null \
                       -i "$repo_root/secrets/demo-ssh-key" \
                       -o IdentitiesOnly=yes \
                       -o ConnectTimeout=2 \
                       root@localhost \
                       cat /var/lib/nixfleet-release/key.pub.b64 2>/dev/null); then
            break
          fi
          # Progress every 30s so the operator knows we're still trying.
          if [ $((i % 30)) -eq 0 ]; then
            echo "    (still polling: ''${i}s elapsed; first-boot services may still be initialising)"
          fi
          sleep 1
        done
        if [ -z "$b64" ]; then
          echo "forge did not surface /var/lib/nixfleet-release/key.pub.b64 within 180s." >&2
          echo "Hint: ssh -p 2202 root@localhost journalctl -u nixfleet-release-keygen" >&2
          exit 1
        fi
        # Find the current public-key line in trust.nix (placeholder or
        # previously-fetched). Idempotent: if forge's key matches what
        # the file already holds, exit clean without a churn commit.
        current=$(grep -oE 'public = "[^"]+";' "$trust_file" | head -1 | sed -E 's/public = "([^"]+)";/\1/')
        if [ "$current" = "$b64" ]; then
          echo "trust.nix already pinned to forge's current pubkey - no change."
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
        # Probe Forgejo SSH with a real git command - `ssh ... true` always
        # exits 1 because Forgejo SSH only handles git protocol commands.
        if ! git ls-remote "git@localhost:demo/fleet.git" HEAD >/dev/null 2>&1; then
          echo "forge Forgejo SSH not reachable on 2222 - run \`nix run .#start-vm -- -h forge\` first." >&2
          echo "If forge is up, the admin user / key / repo bootstrap may not be done yet." >&2
          echo "Watch: ssh -p 2202 root@localhost 'systemctl status forgejo-ssh-keys forgejo-repositories'" >&2
          exit 1
        fi
        ( cd "$repo_root" && git push --force "git@localhost:demo/fleet.git" HEAD:main )
      '';
    };

    # Fleet-up orchestrator: one command, takes a fresh checkout to a
    # fully-converged fleet with the first CI push in flight. Handles:
    #   - Isolating ssh-agent (operator's busy agent stays untouched)
    #   - Regenerating identity if missing
    #   - Tearing down the installer QEMU after each build-vm (the
    #     upstream framework leaves it daemonised on the same pidfile
    #     that start-vm checks; without this teardown start-vm reports
    #     "already running" but it's actually the installer ISO)
    #   - Polling fetch-release-key with progress (cold first boot can
    #     exceed 60s while forgejo init + nix-store optimisation run)
    #   - Running every nix-run subcommand in the isolated agent context
    #
    # See companions: fleet-promote (step 9), fleet-rollback (step 10),
    # fleet-down (clean up everything).
    fleetUp = pkgs.writeShellApplication {
      name = "fleet-up";
      runtimeInputs = [pkgs.openssh pkgs.coreutils pkgs.bash pkgs.git pkgs.nix];
      text = ''
                set -euo pipefail

                # Re-exec under a fresh ssh-agent if not already isolated. The
                # operator's interactive agent (yubikey + work keys + ...) is
                # never touched; this isolated agent dies when the script ends.
                if [ -z "''${_NIXFLEET_DEMO_ISOLATED:-}" ]; then
                  export _NIXFLEET_DEMO_ISOLATED=1
                  exec ssh-agent "$0" "$@"
                fi

                repo_root="$(git rev-parse --show-toplevel)"
                ssh_key="$repo_root/secrets/demo-ssh-key"
                cd "$repo_root"

                # Step 0: regenerate identity if missing (idempotent).
                # Fresh clones already have a committed v0.2 demo identity,
                # so this only fires after `regenerate-demo-identity.sh
                # --force` rotation or a `git clean -fdx`.
                if [ ! -f "$ssh_key" ]; then
                  echo "==> [$(date +%H:%M:%S)] Generating demo identity (first run)"
                  bash "$repo_root/secrets/regenerate-demo-identity.sh"
                fi
                # git checkout restores tracked files at 0644; ssh-add and
                # age-keygen refuse private keys looser than 0600. Enforce
                # every run, idempotently.
                chmod 600 secrets/demo-ssh-key secrets/age-identity.txt
                ssh-add "$ssh_key" 2>&1

                # Helper: kill the daemonised installer QEMU that build-vm leaves
                # behind. Without this, start-vm sees pid alive and silently
                # no-ops, leaving forge on the transient installer instead of
                # the installed disk - fetch-release-key then times out.
                teardown_qemu() {
                  local h="$1"
                  local pidfile="''${XDG_DATA_HOME:-$HOME/.local/share}/nixfleet/vms/$h.pid"
                  if [ -f "$pidfile" ]; then
                    local pid
                    pid=$(cat "$pidfile" 2>/dev/null || true)
                    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                      kill "$pid" 2>/dev/null || true
                      for _ in 1 2 3 4 5; do
                        kill -0 "$pid" 2>/dev/null || break
                        sleep 1
                      done
                    fi
                    rm -f "$pidfile"
                  fi
                }

                # Step 1: build forge FIRST (15G disk for CI store)
                echo
                echo "==> [$(date +%H:%M:%S)] build-vm forge (15G)"
                nix run .#build-vm -- -h forge --identity-key secrets/demo-ssh-key --disk-size 15G
                teardown_qemu forge

                # Step 2: boot forge - regenerates release-signing keypair on first boot
                echo
                echo "==> [$(date +%H:%M:%S)] start-vm forge"
                nix run .#start-vm -- -h forge --vlan 1234

                # Step 3: fetch release key into modules/trust.nix BEFORE building
                # downstream hosts. Otherwise cp/web-NN closures bake the placeholder
                # trust pin and CP rejects every CI signature as BadSignature. Order
                # matters: per the README's Cleanup section.
                echo
                echo "==> [$(date +%H:%M:%S)] fetch-release-key (rotates modules/trust.nix to forge's actual pubkey)"
                nix run .#fetch-release-key

                # Step 4: build downstream hosts AFTER trust pin is in place; they
                # bake the rotated pubkey from modules/trust.nix into their closures
                for h in cp web-01 web-02; do
                  echo
                  echo "==> [$(date +%H:%M:%S)] build-vm $h"
                  nix run .#build-vm -- -h "$h" --identity-key secrets/demo-ssh-key
                  teardown_qemu "$h"
                done

                # Step 5: boot the rest
                for h in cp web-01 web-02; do
                  echo
                  echo "==> [$(date +%H:%M:%S)] start-vm $h"
                  nix run .#start-vm -- -h "$h" --vlan 1234
                done

                # Step 6: provision secrets
                echo
                echo "==> [$(date +%H:%M:%S)] provision-secrets --all"
                nix run .#provision-secrets -- --all

                # Step 7: push to forge -> triggers CI
                echo
                echo "==> [$(date +%H:%M:%S)] push-repo"
                nix run .#push-repo

                cat <<EOF

        ============================================================
        Fleet up. CI on forge is building the first signed manifest.
        Cold first push: ~20-45 min (Rust workspace + 4 NixOS closures).

        Watch CI (web UI, easiest):
          http://localhost:3001/demo/fleet/actions

        Or via journal (in another terminal):
          ssh -p 2202 -o IdentityAgent=none -o IdentitiesOnly=yes \\
              -i secrets/demo-ssh-key -o StrictHostKeyChecking=no \\
              -o UserKnownHostsFile=/dev/null root@localhost \\
              'journalctl -u gitea-runner-nixfleet -f --no-pager'

        Watch fleet convergence (once the first sidecar lands):
          ssh -p 2201 -o IdentityAgent=none -o IdentitiesOnly=yes \\
              -i secrets/demo-ssh-key -o StrictHostKeyChecking=no \\
              -o UserKnownHostsFile=/dev/null root@localhost
          # inside cp:
          watch -n 3 nixfleet status

        Next:
          nix run .#fleet-promote    -- wave promotion (step 9 of the walkthrough)
          nix run .#fleet-rollback   -- magic rollback test (step 10)
          nix run .#fleet-recover    -- revert the rollback test commit
          nix run .#fleet-down       -- stop + clean every VM
        ============================================================
        EOF
      '';
    };

    # Step 9 from the walkthrough: bump web-version, commit, push, let
    # the cascade fire. Auto-increments the patch component so subsequent
    # runs keep bumping.
    fleetPromote = pkgs.writeShellApplication {
      name = "fleet-promote";
      runtimeInputs = [pkgs.openssh pkgs.coreutils pkgs.bash pkgs.git pkgs.nix pkgs.gnused pkgs.gnugrep];
      text = ''
                set -euo pipefail
                if [ -z "''${_NIXFLEET_DEMO_ISOLATED:-}" ]; then
                  export _NIXFLEET_DEMO_ISOLATED=1
                  exec ssh-agent "$0" "$@"
                fi
                repo_root="$(git rev-parse --show-toplevel)"
                cd "$repo_root"
                ssh-add "$repo_root/secrets/demo-ssh-key" 2>&1

                if ! git diff-index --quiet HEAD --; then
                  echo "git tree is dirty; commit or stash before fleet-promote" >&2
                  exit 1
                fi

                cur=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' modules/web-version.nix | head -1)
                major=$(echo "$cur" | cut -d. -f1)
                minor=$(echo "$cur" | cut -d. -f2)
                patch=$(echo "$cur" | cut -d. -f3)
                next="$major.$minor.$((patch + 1))"
                echo "==> Bumping web-version: $cur -> $next"
                # The literal in modules/web-version.nix is `"$cur\n"` (escaped backslash-n)
                # inside a Nix double-double-quoted string. We swap the version number only.
                sed -i "s|\"$cur\\\\n\"|\"$next\\\\n\"|" modules/web-version.nix
                grep -q "$next" modules/web-version.nix || { echo "ERROR: failed to bump web-version" >&2; exit 2; }

                git add modules/web-version.nix
                git commit -m "demo(fleet-promote): web tier $cur -> $next"
                nix run .#push-repo

                cat <<EOF

        Promotion pushed. CI rebuilds the web closures and signs the new manifest.
        The cascade order is: web-02 (edge) -> cp (infra, instant - closure unchanged) -> web-01 (stable canary).

        Watch from cp:
          watch -n 3 'nixfleet status; echo; curl -s --max-time 2 http://localhost:2280/version; echo; curl -s --max-time 2 http://localhost:2281/version'

        End state: both web hosts return $next, status table shows all three Converged.
        EOF
      '';
    };

    # Step 10 from the walkthrough: inject an invalid nginx listen on
    # web-01, push, watch the v0.2 safety net fire:
    #   activating -> soaking, probes failing during soak
    #   agent-side sustained-failure detection (RFC-0008 §4.2) -> Failed
    #   agent reads onHealthFailure from manifest -> autonomously reverts
    #   anti-thrash: bad SHA recorded in quarantinedClosure, channel halts
    fleetRollback = pkgs.writeShellApplication {
      name = "fleet-rollback";
      runtimeInputs = [pkgs.openssh pkgs.coreutils pkgs.bash pkgs.git pkgs.nix pkgs.gnused pkgs.gnugrep];
      text = ''
                set -euo pipefail
                if [ -z "''${_NIXFLEET_DEMO_ISOLATED:-}" ]; then
                  export _NIXFLEET_DEMO_ISOLATED=1
                  exec ssh-agent "$0" "$@"
                fi
                repo_root="$(git rev-parse --show-toplevel)"
                cd "$repo_root"
                ssh-add "$repo_root/secrets/demo-ssh-key" 2>&1

                if ! git diff-index --quiet HEAD --; then
                  echo "git tree is dirty; commit or stash before fleet-rollback" >&2
                  exit 1
                fi
                if grep -q "999.999.999.999" hosts/web-01.nix; then
                  echo "bad listen already present in hosts/web-01.nix" >&2
                  echo "Run 'nix run .#fleet-recover' to revert, then retry." >&2
                  exit 1
                fi

                echo "==> Injecting invalid nginx listen on web-01"
                # The block is single-line in the source: 'virtualHosts.default = {default = true;};'.
                # We expand it to include the bad listen attribute.
                sed -i 's|virtualHosts.default = {default = true;};|virtualHosts.default = {default = true; listen = [{addr = "999.999.999.999"; port = 80;}];};|' hosts/web-01.nix
                grep -q "999.999.999.999" hosts/web-01.nix || { echo "ERROR: failed to inject bad listen" >&2; exit 2; }

                git add hosts/web-01.nix
                git commit -m "demo(fleet-rollback): inject invalid nginx listen on web-01"
                nix run .#push-repo

                cat <<EOF

        Bad config pushed. Expected timeline (after CI signs the new manifest, 2-5 min subsequent push):
          1. cp dispatches the bad closure to web-01
          2. web-01 -> activating -> soaking (nginx-pre-start fails on '999.999.999.999:80')
          3. probes start failing -> CLI shows 'warn probes failing' during the soak window
          4. ~120s sustained failure ON THE AGENT -> agent emits Failed event -> CLI shows 'failed'
          5. agent reads onHealthFailure from the signed manifest -> autonomously reverts (no CP RollbackSignal)
          6. CLI shows 'reverted -- channel halted, push fix'; CP quarantines the bad SHA
          7. curl http://localhost:2280/version returns the previous version (no end-user impact)
          8. nixfleet rollout events <id>     # chronological signed event log for the rollout
          9. nixfleet rollout hosts <id>      # per-host state snapshot for the rollout

        Watch from cp:
          watch -n 3 'nixfleet status; echo; curl -s --max-time 2 http://localhost:2280/version'

        When done, recover with:
          nix run .#fleet-recover
        EOF
      '';
    };

    fleetRecover = pkgs.writeShellApplication {
      name = "fleet-recover";
      runtimeInputs = [pkgs.openssh pkgs.coreutils pkgs.bash pkgs.git pkgs.nix pkgs.gnused pkgs.gnugrep];
      text = ''
        set -euo pipefail
        if [ -z "''${_NIXFLEET_DEMO_ISOLATED:-}" ]; then
          export _NIXFLEET_DEMO_ISOLATED=1
          exec ssh-agent "$0" "$@"
        fi
        repo_root="$(git rev-parse --show-toplevel)"
        cd "$repo_root"
        ssh-add "$repo_root/secrets/demo-ssh-key" 2>&1

        if ! grep -q "999.999.999.999" hosts/web-01.nix; then
          echo "no bad listen to revert in hosts/web-01.nix" >&2
          exit 0
        fi
        echo "==> Reverting bad nginx listen"
        sed -i 's|virtualHosts.default = {default = true; listen = \[{addr = "999.999.999.999"; port = 80;}\];};|virtualHosts.default = {default = true;};|' hosts/web-01.nix
        grep -q "999.999.999.999" hosts/web-01.nix && { echo "ERROR: revert failed; bad listen still present" >&2; exit 2; }

        git add hosts/web-01.nix
        git commit -m "demo(fleet-recover): revert bad nginx listen"
        nix run .#push-repo
        echo
        echo "Recovery pushed. Channel halt should lift on the new declared SHA"
        echo "(different from quarantinedClosure). Web-01 promotes through activating -> soaking -> converged"
        echo "on the good closure. curl http://localhost:2280/version returns the version again."
      '';
    };

    fleetDown = pkgs.writeShellApplication {
      name = "fleet-down";
      runtimeInputs = [pkgs.coreutils pkgs.bash pkgs.git pkgs.nix];
      text = ''
        set -euo pipefail
        cd "$(git rev-parse --show-toplevel)"
        echo "==> Stopping all VMs"
        nix run .#stop-vm -- --all || true
        # Belt-and-suspenders: kill any lingering qemu (build-vm leaves
        # installer ISO qemus on the same pidfile path).
        for h in forge cp web-01 web-02; do
          pidfile="''${XDG_DATA_HOME:-$HOME/.local/share}/nixfleet/vms/$h.pid"
          if [ -f "$pidfile" ]; then
            pid=$(cat "$pidfile" 2>/dev/null || true)
            [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
            rm -f "$pidfile"
          fi
        done
        echo "==> Cleaning qcow2 disks"
        nix run .#clean-vm -- --all || true
        echo
        echo "Fleet down. Run 'nix run .#fleet-up' to start fresh."
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
          echo "==> cp: staging fleet CA + operator cert + demo SSH key"
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
          # demo-ssh-key: cp uses this to push to forge's Forgejo from
          # the operator workflow (cp's ssh_config Host forge entry
          # points IdentityFile at this path).
          stage "$repo_root/secrets/demo-ssh-key"     /var/lib/nixfleet-demo/demo-ssh-key     0600
          # Agent identity material: cp also runs an agent that reports
          # to its own /v1/* over loopback (see hosts/cp.nix).
          stage "$repo_root/secrets/host-keys/cp"                 /var/lib/nixfleet-demo/agent-client.key     0600
          stage "$repo_root/secrets/bootstrap-tokens/cp.json"     /var/lib/nixfleet-demo/bootstrap-token.json 0600
          echo "==> cp: starting gated services"
          ssh "''${ssh_opts[@]}" -p "$port" root@localhost \
            "systemctl start nixfleet-cp-tls-keygen && systemctl restart nixfleet-control-plane && systemctl restart nixfleet-agent"
          echo "    cp: provisioning complete."
        }

        provision_forge() {
          local port; port=$(ssh_port_for forge)
          echo "==> forge: staging cache signing key"
          wait_for_ssh forge
          stage() {
            local src="$1" dst="$2" mode="$3"
            ssh "''${ssh_opts[@]}" -p "$port" root@localhost \
              "mkdir -p /var/lib/nixfleet-demo && install -m $mode /dev/stdin $dst" \
              < "$src"
          }
          # cache-signing-key: harmonia signs closures served from
          # forge's /nix/store with this key; agent hosts trust the
          # matching pubkey (baked into closures via
          # modules/use-forge-cache.nix).
          stage "$repo_root/secrets/cache-signing-key" /var/lib/nixfleet-demo/cache-signing-key 0600
          echo "==> forge: starting harmonia"
          ssh "''${ssh_opts[@]}" -p "$port" root@localhost \
            "systemctl restart harmonia"
          echo "    forge: provisioning complete."
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
          provision_forge
          provision_web web-01
          provision_web web-02
        else
          case "$host" in
            cp)             provision_cp ;;
            forge)          provision_forge ;;
            web-01|web-02)  provision_web "$host" ;;
            *)              echo "unknown host: $host" >&2; exit 2 ;;
          esac
        fi
      '';
    };
  in {
    # Expose the bastion VM as a package so apps.default can `nix build`
    # it by path without going through flake.nixosConfigurations (which
    # would shift mkVmApps' port assignment for the fleet hosts).
    packages.bastion-vm = bastion.config.system.build.vm;

    apps =
      vmApps
      // {
        default = {
          type = "app";
          program = "${runBastion}/bin/nixfleet-demo";
          meta.description = "Single-host compliance demo: one NixOS VM, NIS2-essential preset, signed evidence. ~2-5 min.";
        };
        fleet = {
          type = "app";
          program = "${fleetInfo}/bin/nixfleet-demo-fleet";
          meta.description = "Print the 4-VM reference fleet walkthrough (45-90 min on cold cache, 10 steps).";
        };
        fleet-up = {
          type = "app";
          program = "${fleetUp}/bin/fleet-up";
          meta.description = "One-shot fleet orchestrator: identity + build + start + provision + push. ~30-45 min cold.";
        };
        fleet-promote = {
          type = "app";
          program = "${fleetPromote}/bin/fleet-promote";
          meta.description = "Step 9: bump web-version, commit, push. Drives the cascade through three channels.";
        };
        fleet-rollback = {
          type = "app";
          program = "${fleetRollback}/bin/fleet-rollback";
          meta.description = "Step 10: inject invalid nginx listen on web-01 to exercise probe gate + sweep + auto-rollback + quarantine + channel halt.";
        };
        fleet-recover = {
          type = "app";
          program = "${fleetRecover}/bin/fleet-recover";
          meta.description = "Revert the fleet-rollback test commit and unblock the halted channel.";
        };
        fleet-down = {
          type = "app";
          program = "${fleetDown}/bin/fleet-down";
          meta.description = "Stop + clean every VM. Pairs with fleet-up for a fresh cycle.";
        };
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
          meta.description = "Phase 5 secrets staging: scp host-keys + bootstrap-tokens + demo-ssh-key into each VM's /var/lib/nixfleet-demo/.";
        };
      };
  };
}
