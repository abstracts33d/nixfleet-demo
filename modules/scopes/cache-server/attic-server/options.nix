# Attic binary cache server scope — option declarations.
{lib, ...}: let
  types = lib.types;
in {
  options.nixfleet.atticServer = {
    enable = lib.mkEnableOption "Attic binary cache server";

    package = lib.mkOption {
      type = types.package;
      description = ''
        atticd package. Pass e.g.
        `inputs.attic.packages.''${system}.attic-server` from the
        consumer flake — the scope cannot reference the attic flake
        input directly because the scope's module function receives
        the consumer's specialArgs, not the scope flake's own inputs.
      '';
    };

    domain = lib.mkOption {
      type = types.str;
      example = "cache.example.org";
      description = "Public domain for the cache (used by downstream consumers for substituter URLs).";
    };

    listen = lib.mkOption {
      type = types.str;
      default = "127.0.0.1:8081";
      description = "Bind address:port. Use 127.0.0.1 when fronted by a reverse proxy.";
    };

    openFirewall = lib.mkOption {
      type = types.bool;
      default = false;
      description = "Open the listen port in the firewall. Disable when a reverse proxy fronts the service.";
    };

    dbPath = lib.mkOption {
      type = types.str;
      default = "/var/lib/nixfleet-attic/server.db";
      description = "SQLite database path.";
    };

    signing.privateKeyFile = lib.mkOption {
      type = types.str;
      example = "/run/secrets/attic-signing-key";
      description = "Path to the ed25519 private key the cache signs closures with.";
    };

    storage = {
      type = lib.mkOption {
        type = types.enum ["local" "s3"];
        default = "local";
      };
      local.path = lib.mkOption {
        type = types.str;
        default = "/var/lib/nixfleet-attic/storage";
      };
      s3 = {
        bucket = lib.mkOption {
          type = types.str;
          default = "";
        };
        region = lib.mkOption {
          type = types.str;
          default = "";
        };
        endpoint = lib.mkOption {
          type = types.nullOr types.str;
          default = null;
        };
      };
    };

    garbageCollection = {
      schedule = lib.mkOption {
        type = types.str;
        default = "weekly";
      };
      keepSinceLastPush = lib.mkOption {
        type = types.str;
        default = "90 days";
      };
    };
  };
}
