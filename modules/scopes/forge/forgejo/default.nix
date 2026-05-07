# Forgejo git forge scope.
#
# HTTP listens on loopback by default — consumer wires the reverse
# proxy (Caddy, nginx, ...). SSH binds a separate port (222 default)
# so the host's OpenSSH keeps :22.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.nixfleet.forge;
in {
  imports = [./options.nix];

  config = lib.mkIf cfg.enable {
    services.forgejo = {
      enable = true;
      stateDir = cfg.dataDir;
      database.type = cfg.database.type;
      inherit (cfg) lfs;

      settings = {
        DEFAULT.APP_NAME = cfg.appName;

        server = {
          DOMAIN = cfg.domain;
          ROOT_URL = "https://${cfg.domain}/";
          HTTP_ADDR = cfg.http.addr;
          HTTP_PORT = cfg.http.port;
          SSH_DOMAIN = cfg.domain;
          SSH_PORT = cfg.ssh.port;
          SSH_LISTEN_HOST = cfg.ssh.listenHost;
          START_SSH_SERVER = cfg.ssh.enable;
          # Override NixOS's default of service-user-as-SSH-username so
          # clients can use `git@<host>` per the Forgejo/Gitea/GitHub/
          # GitLab convention. Matches cfg.ssh.user (default "git").
          # Not a system user — just a magic string Forgejo matches on
          # incoming SSH auth.
          BUILTIN_SSH_SERVER_USER = cfg.ssh.user;
          SSH_USER = cfg.ssh.user;
          LANDING_PAGE = "login";
        };

        service.DISABLE_REGISTRATION = cfg.disableRegistration;
        session.COOKIE_SECURE = true;

        actions = lib.mkIf cfg.actions.enable {
          ENABLED = true;
          DEFAULT_ACTIONS_URL = cfg.actions.defaultActionsUrl;
        };

        mailer = lib.mkIf cfg.smtp.enable {
          ENABLED = true;
          SMTP_ADDR = cfg.smtp.host;
          FROM = cfg.smtp.from;
          USER = cfg.smtp.user;
          PASSWD = lib.mkIf (cfg.smtp.passwordFile != null) "$(cat ${cfg.smtp.passwordFile})";
        };

        repository.DEFAULT_BRANCH = "main";
      };
    };

    # Optional bootstrap admin creation on first start, plus declarative
    # SSH-key registration on every start via the Forgejo HTTP API.
    #
    # Why API, not CLI: Forgejo LTS 11 (and earlier) has no
    # `admin user add-ssh-key` CLI subcommand — that was added in later
    # majors. The HTTP API surface is stable across versions, so we
    # generate a bootstrap access token once (via the CLI, which does
    # have `admin user generate-access-token`) and use it for both the
    # SSH-key loop here and the repositories oneshot below.
    systemd.services.forgejo = lib.mkIf (cfg.admin.userFile != null) {
      path = [pkgs.curl pkgs.jq pkgs.gnugrep pkgs.coreutils];
      preStart = lib.mkAfter ''
        admin_user=""
        if [ ! -f ${cfg.dataDir}/.nixfleet-admin-created ]; then
          if [ -r ${cfg.admin.userFile} ]; then
            IFS=: read -r admin_user admin_email admin_pass < ${cfg.admin.userFile}
            ${pkgs.forgejo}/bin/forgejo admin user create \
              --admin \
              --username "$admin_user" \
              --email "$admin_email" \
              --password "$admin_pass" || true
            touch ${cfg.dataDir}/.nixfleet-admin-created
          fi
        fi

        # Ensure admin_user is set for downstream steps, re-reading if
        # the marker-skipped branch above didn't populate it.
        if [ -z "$admin_user" ] && [ -r ${cfg.admin.userFile} ]; then
          IFS=: read -r admin_user _ _ < ${cfg.admin.userFile}
        fi

        # Bootstrap API token. Generated once; reused for every later
        # API call in this scope (SSH keys, repos). The file is
        # forgejo:forgejo 0600 — never exposed outside the service.
        token_file=${cfg.dataDir}/.nixfleet-bootstrap-token
        if [ -n "$admin_user" ] && [ ! -f "$token_file" ]; then
          # generate-access-token prints a line like
          #   "Access token was successfully created: <40-hex>"
          # Parse the 40-hex-char token out of stdout.
          token=$(${pkgs.forgejo}/bin/forgejo admin user generate-access-token \
            --username "$admin_user" \
            --token-name nixfleet-bootstrap \
            --scopes "write:admin,write:repository,write:user" 2>&1 \
            | grep -oE '[0-9a-f]{40}' | head -1) || true
          if [ -n "$token" ]; then
            umask 077
            printf '%s' "$token" > "$token_file"
          fi
        fi

        # NOTE: sshKeyFiles registration moved to forgejo-ssh-keys.service
        # because the HTTP API it calls isn't reachable during preStart
        # (forgejo's HTTP listener only comes up after preStart returns).
        # The token written here is consumed by that separate oneshot.
      '';
    };

    # Declarative admin SSH-key registration. Moved out of
    # forgejo.service preStart (HTTP listener not yet up during
    # preStart → curl fails with HTTP 0). Gated on the admin marker,
    # the bootstrap token, AND an HTTP-ready probe — see below.
    systemd.services.forgejo-ssh-keys = lib.mkIf (cfg.admin.sshKeyFiles != []) {
      description = "Declarative Forgejo admin SSH key registration";
      after = ["forgejo.service"];
      wants = ["forgejo.service"];
      wantedBy = ["multi-user.target"];
      path = [pkgs.curl pkgs.jq pkgs.coreutils];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "forgejo";
        Group = "forgejo";
      };

      script = ''
        set -u

        # Gate: wait (bounded) for admin marker, bootstrap token, AND
        # the HTTP API to actually accept connections. `After=
        # forgejo.service` only guarantees forgejo.service reached
        # "active" — Type=simple services declare active as soon as
        # ExecStart spawns, which happens before Forgejo has finished
        # binding its HTTP socket.
        waited=0
        while [ ! -f ${cfg.dataDir}/.nixfleet-admin-created ] \
           || [ ! -f ${cfg.dataDir}/.nixfleet-bootstrap-token ] \
           || ! curl -sf -o /dev/null "http://127.0.0.1:${toString cfg.http.port}/api/v1/version"; do
          if [ $waited -ge 60 ]; then
            echo "forge-ssh-keys: marker/token/HTTP not ready after 60s, aborting" >&2
            exit 0
          fi
          sleep 1
          waited=$((waited + 1))
        done

        IFS=: read -r admin_user _ _ < ${cfg.admin.userFile}
        token=$(cat ${cfg.dataDir}/.nixfleet-bootstrap-token)

        ${lib.concatMapStringsSep "\n" (keyFile: ''
            if [ -r ${keyFile} ]; then
              key_content="$(cat ${keyFile})"
              if [ -n "$key_content" ]; then
                echo "forge-ssh-keys: registering ${keyFile} for $admin_user" >&2
                # POST /api/v1/admin/users/<name>/keys — 201 Created on
                # success, 422 on duplicate fingerprint. Both treated as
                # "already in good state."
                body=$(jq -nc \
                  --arg title "nixfleet-bootstrap-$(basename ${keyFile} .pub)" \
                  --arg key "$key_content" \
                  '{title: $title, key: $key}')
                status=$(curl -s -o /dev/null -w '%{http_code}' \
                  -H "Authorization: token $token" \
                  -H "Content-Type: application/json" \
                  -d "$body" \
                  "http://127.0.0.1:${toString cfg.http.port}/api/v1/admin/users/$admin_user/keys") || status=0
                case "$status" in
                  201|422) echo "forge-ssh-keys: ${keyFile} -> HTTP $status (ok)" >&2 ;;
                  *) echo "forge-ssh-keys: ${keyFile} -> HTTP $status (failed)" >&2 ;;
                esac
              fi
            else
              echo "forge-ssh-keys: ${keyFile} not readable, skipping" >&2
            fi
          '')
          cfg.admin.sshKeyFiles}
      '';
    };

    # Declarative repository pre-creation. Runs after forgejo.service is
    # active, gated on the admin-created marker, the bootstrap token,
    # AND the HTTP API readiness probe (same reason as ssh-keys above).
    # Uses the Forgejo HTTP API (`admin repo create` CLI subcommand
    # does not exist on LTS 11).
    #
    # TODO(v2): extend the submodule + this unit with pullMirror support
    # (upstream URL + auth) so declared repos can be pull-mirrors of
    # external sources. Out of scope for v1.
    systemd.services.forgejo-repositories = lib.mkIf (cfg.repositories != []) {
      description = "Declarative Forgejo repository pre-creation";
      after = ["forgejo.service"];
      wants = ["forgejo.service"];
      wantedBy = ["multi-user.target"];
      path = [pkgs.curl pkgs.jq pkgs.coreutils];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "forgejo";
        Group = "forgejo";
      };

      script = ''
        set -u

        # Gate: admin marker + bootstrap token + HTTP API ready.
        waited=0
        while [ ! -f ${cfg.dataDir}/.nixfleet-admin-created ] \
           || [ ! -f ${cfg.dataDir}/.nixfleet-bootstrap-token ] \
           || ! curl -sf -o /dev/null "http://127.0.0.1:${toString cfg.http.port}/api/v1/version"; do
          if [ $waited -ge 60 ]; then
            echo "forge-repositories: marker/token/HTTP not ready after 60s, aborting" >&2
            exit 0
          fi
          sleep 1
          waited=$((waited + 1))
        done
        token=$(cat ${cfg.dataDir}/.nixfleet-bootstrap-token)

        ${lib.concatMapStringsSep "\n" (repo: ''
            if [ -d ${cfg.dataDir}/repositories/${repo.owner}/${repo.name}.git ]; then
              echo "forge-repositories: ${repo.owner}/${repo.name} already exists, skipping" >&2
            else
              echo "forge-repositories: creating ${repo.owner}/${repo.name}" >&2
              # POST /api/v1/admin/users/<owner>/repos — 201 Created on
              # success. 422 (duplicate) is treated as "already ok" even
              # though the on-disk check above should have caught it.
              body=$(jq -nc \
                --arg name ${lib.escapeShellArg repo.name} \
                --arg desc ${lib.escapeShellArg repo.description} \
                --arg branch ${lib.escapeShellArg repo.defaultBranch} \
                --argjson private ${
              if repo.private
              then "true"
              else "false"
            } \
                '{name: $name, description: $desc, default_branch: $branch, private: $private, auto_init: false}')
              status=$(curl -s -o /dev/null -w '%{http_code}' \
                -H "Authorization: token $token" \
                -H "Content-Type: application/json" \
                -d "$body" \
                "http://127.0.0.1:${toString cfg.http.port}/api/v1/admin/users/${repo.owner}/repos") || status=0
              case "$status" in
                201|422) echo "forge-repositories: ${repo.owner}/${repo.name} -> HTTP $status (ok)" >&2 ;;
                *) echo "forge-repositories: ${repo.owner}/${repo.name} -> HTTP $status (failed)" >&2 ;;
              esac
            fi
          '')
          cfg.repositories}
      '';
    };

    # Forgejo's integrated SSH server binds cfg.ssh.port as the
    # unprivileged `forgejo` user. Ports <1024 are privileged by default.
    # The NixOS forgejo module sets NoNewPrivileges=true, which prevents
    # AmbientCapabilities=CAP_NET_BIND_SERVICE from taking effect at exec
    # time. Lower the unprivileged-port-start sysctl instead so any
    # user-space process can bind cfg.ssh.port without needing caps.
    boot.kernel.sysctl = lib.mkIf (cfg.ssh.enable && cfg.ssh.port < 1024) {
      "net.ipv4.ip_unprivileged_port_start" = cfg.ssh.port;
    };

    # Open the Forgejo SSH port in the system firewall when requested.
    # Without this, git clients hit a TCP-level black hole: forgejo
    # listens on *:<port>, but nftables silently drops SYNs from
    # anything except loopback.
    networking.firewall.allowedTCPPorts = lib.mkIf (cfg.ssh.enable && cfg.ssh.openFirewall) [cfg.ssh.port];

    nixfleet.persistence.directories = [
      {
        directory = cfg.dataDir;
        user = "forgejo";
        group = "forgejo";
        mode = "0750";
      }
    ];

    # forgejo-secrets.service's systemd sandbox bind-mounts stateDir/custom
    # read-write into its namespace. On a fresh stateDir (first boot on an
    # impermanent host, or a bare install), the subdirectory doesn't exist
    # yet and the namespace setup fails with status=226/NAMESPACE. Pre-create
    # it via tmpfiles so the sandbox has something to bind.
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir}/custom 0750 forgejo forgejo - -"
    ];
  };
}
