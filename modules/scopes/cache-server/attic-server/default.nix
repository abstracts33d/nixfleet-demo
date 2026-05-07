# Attic binary cache server scope.
# atticd is supplied by the consumer via nixfleet.atticServer.package —
# typically `inputs.attic.packages.''${system}.attic-server` where
# `attic` is a flake input of the consumer.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.nixfleet.atticServer;

  storageBlock =
    if cfg.storage.type == "local"
    then ''
      type = "local"
      path = "${cfg.storage.local.path}"
    ''
    else ''
      type = "s3"
      bucket = "${cfg.storage.s3.bucket}"
      region = "${cfg.storage.s3.region}"
      ${lib.optionalString (cfg.storage.s3.endpoint != null) ''endpoint = "${cfg.storage.s3.endpoint}"''}
    '';

  serverToml = pkgs.writeText "attic-server.toml" ''
    listen = "${cfg.listen}"

    [database]
    url = "sqlite://${cfg.dbPath}?mode=rwc"

    [storage]
    ${storageBlock}

    [garbage-collection]
    default-retention-period = "${cfg.garbageCollection.keepSinceLastPush}"

    [jwt.signing]
    token-hs256-secret-base64 = "dW51c2VkLXBsYWNlaG9sZGVyLWZvci1hdHRpYy1zZXJ2ZXI="

    [chunking]
    nar-size-threshold = 65536
    min-size = 16384
    avg-size = 65536
    max-size = 262144
  '';
in {
  imports = [./options.nix];

  config = lib.mkIf cfg.enable {
    systemd.services.nixfleet-attic-server = {
      description = "NixFleet Attic Binary Cache Server";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/atticd --config ${serverToml}";
        Restart = "always";
        RestartSec = 10;
        StateDirectory = "nixfleet-attic";

        NoNewPrivileges = true;
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ReadWritePaths = ["/var/lib/nixfleet-attic"];

        LoadCredential = "signing-key:${cfg.signing.privateKeyFile}";
      };
    };

    systemd.timers.nixfleet-attic-gc = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = cfg.garbageCollection.schedule;
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };

    systemd.services.nixfleet-attic-gc = {
      description = "NixFleet Attic Garbage Collection";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${cfg.package}/bin/atticd --config ${serverToml} --mode garbage-collector-once";
        ReadWritePaths = ["/var/lib/nixfleet-attic"];
      };
    };

    networking.firewall.allowedTCPPorts = let
      port = lib.toInt (lib.last (lib.splitString ":" cfg.listen));
    in
      lib.mkIf cfg.openFirewall [port];

    nixfleet.persistence.directories = ["/var/lib/nixfleet-attic"];
  };
}
