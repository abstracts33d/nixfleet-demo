# Forge scope - option declarations.
{lib, ...}: let
  types = lib.types;
in {
  options.nixfleet.forge = {
    enable = lib.mkEnableOption "Forgejo self-hosted git forge";

    domain = lib.mkOption {
      type = types.str;
      example = "git.example.org";
      description = "Public domain for the forge. Used for DOMAIN + ROOT_URL generation.";
    };

    appName = lib.mkOption {
      type = types.str;
      default = "Forgejo";
      description = "Display name shown in the forge UI.";
    };

    dataDir = lib.mkOption {
      type = types.str;
      default = "/var/lib/forgejo";
      description = "State directory for the forge.";
    };

    http = {
      addr = lib.mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "HTTP listen address. Defaults to loopback on the assumption a reverse proxy handles TLS.";
      };
      port = lib.mkOption {
        type = types.port;
        default = 3001;
        description = "HTTP listen port.";
      };
    };

    ssh = {
      enable = lib.mkOption {
        type = types.bool;
        default = true;
        description = "Run Forgejo's integrated SSH server for git push/clone.";
      };
      port = lib.mkOption {
        type = types.port;
        default = 222;
        description = "Forgejo SSH listen port. Keep separate from OpenSSH (22).";
      };
      listenHost = lib.mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "Forgejo SSH bind address.";
      };
      openFirewall = lib.mkOption {
        type = types.bool;
        default = true;
        description = ''
          Open the Forgejo SSH port in the system firewall. Defaults to
          `true` - the natural use of this scope is to expose
          `git push/clone` via SSH. Without this, incoming connections
          are silently dropped (port listens but firewall rejects).
          Set to `false` only if SSH is proxied through another
          mechanism (bastion, Tailscale, etc.).
        '';
      };
      user = lib.mkOption {
        type = types.str;
        default = "git";
        description = ''
          SSH username clients connect as - typically `git@` per the
          Forgejo/Gitea/GitHub/GitLab convention. Forgejo's NixOS
          module defaults this to the service user (`forgejo`), which
          breaks muscle memory for everyone who's ever cloned a repo.
          Override here so `git@forge-host:owner/repo.git` works out of
          the box. Not a system user - just a magic string Forgejo
          matches on incoming SSH auth.
        '';
      };
    };

    actions = {
      enable = lib.mkOption {
        type = types.bool;
        default = true;
        description = "Enable Forgejo Actions (native CI).";
      };
      defaultActionsUrl = lib.mkOption {
        type = types.str;
        default = "github";
        description = "Where to fetch reusable actions from. \"github\" = fetch github.com/actions/*; \"self\" = require mirrors in Forgejo.";
      };
    };

    disableRegistration = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Disable open user registration. Single-operator / invite-only posture.";
    };

    database.type = lib.mkOption {
      type = types.enum ["sqlite3" "postgres" "mysql"];
      default = "sqlite3";
      description = "Database backend.";
    };

    lfs.enable = lib.mkOption {
      type = types.bool;
      default = true;
      description = "Enable Git LFS support.";
    };

    smtp = {
      enable = lib.mkOption {
        type = types.bool;
        default = false;
        description = "Enable outbound SMTP for notifications.";
      };
      host = lib.mkOption {
        type = types.str;
        default = "";
        example = "smtp.example.com:587";
        description = "SMTP host (host:port).";
      };
      from = lib.mkOption {
        type = types.str;
        default = "";
        example = "forge@example.com";
        description = "MAIL FROM address.";
      };
      user = lib.mkOption {
        type = types.str;
        default = "";
        description = "SMTP auth user.";
      };
      passwordFile = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "File containing the SMTP auth password.";
      };
    };

    admin = {
      userFile = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Optional file containing the bootstrap admin credentials (\"USER:EMAIL:PASSWORD\" on one line). When set, Forgejo creates the admin on first start.";
      };
      sshKeyFiles = lib.mkOption {
        type = types.listOf types.path;
        default = [];
        description = ''
          List of file paths, each containing one SSH public key to register
          on the admin user's Forgejo account. Files are read at service
          start time - typically agenix-decrypted paths under /run/agenix/.
          Registration is idempotent (Forgejo dedupes on fingerprint); safe
          to re-run on every deploy. Only applied after `admin.userFile`
          has successfully created the admin user.
        '';
        example = ["/run/agenix/forgejo-admin-sshkey"];
      };
    };

    repositories = lib.mkOption {
      type = types.listOf (types.submodule {
        options = {
          owner = lib.mkOption {
            type = types.str;
            description = "Forgejo user or organization that owns the repository. MUST already exist as a Forgejo user - typically created via `admin.userFile`.";
          };
          name = lib.mkOption {
            type = types.str;
            description = "Repository name (the path segment after the owner).";
          };
          description = lib.mkOption {
            type = types.str;
            default = "";
            description = "Optional repository description.";
          };
          private = lib.mkOption {
            type = types.bool;
            default = false;
            description = "Create the repository as private.";
          };
          defaultBranch = lib.mkOption {
            type = types.str;
            default = "main";
            description = "Default branch name.";
          };
        };
      });
      default = [];
      description = ''
        Repositories to ensure exist on this Forgejo instance. Created
        once after the admin user exists; idempotent on subsequent
        deploys (existing repos are skipped). The declared owner MUST
        already exist as a Forgejo user - typically `admin.userFile`
        created them.
      '';
      example = [
        {
          owner = "demo";
          name = "fleet";
          description = "NixOS fleet config";
        }
      ];
    };
  };
}
