# Demo fleet - 6 hosts consuming nixfleet via mkHost.
{inputs, ...}: let
  mkHost = inputs.nixfleet.lib.mkHost;
  scopes = inputs.nixfleet.scopes;

  inherit (import ./modules/org-defaults.nix) orgDefaults orgOperators;

  # Scopes imported into every host.
  fleetModules = [
    scopes.roles.server
    scopes.operators
    scopes.o11y
    scopes.compliance
    scopes.generation-label
    scopes.terminal-compat
    scopes.monitoring-server
    scopes.disko
    orgOperators
    (import ./modules/compliance.nix {inherit inputs;})
    (import ./modules/secrets.nix inputs.agenix.nixosModules.default)
    ./modules/tls.nix
    ./modules/monitoring.nix
    ./modules/web-server.nix
    ./modules/vm-network.nix
    ./modules/cache.nix
    # Enable scopes fleet-wide
    {
      nixfleet.o11y.metrics.enable = true;
      nixfleet.monitoring.nodeExporter.openFirewall = true;
      nixfleet.compliance.enable = true;
      nixfleet.generationLabel.enable = true;
      nixfleet.terminalCompat.enable = true;
      # Fast poll + health checks for demo recordings (defaults: 60s)
      services.nixfleet-agent.pollInterval = 10;
      services.nixfleet-agent.healthInterval = 10;
    }
  ];

  hostModules = name:
    fleetModules
    ++ [
      ./hosts/${name}/hardware-configuration.nix
      ./hosts/${name}/disk-config.nix
    ];

  # Inline module for impermanent hosts.
  impermanent = {nixfleet.impermanence.enable = true;};
in {
  flake.nixosConfigurations = {
    cp-01 = mkHost {
      hostName = "cp-01";
      platform = "x86_64-linux";
      hostSpec = orgDefaults;
      modules =
        hostModules "cp-01"
        ++ [
          impermanent
          ({pkgs, ...}: {
            services.nixfleet-control-plane = {
              enable = true;
              openFirewall = true;
            };
            environment.systemPackages = [
              inputs.nixfleet.packages.x86_64-linux.nixfleet-cli
              pkgs.jq
            ];
            environment.etc."nixfleet-demo/fleet".source = inputs.self;

            # Wire demo operator SSH key for root (push to cache, SSH deploys)
            programs.ssh.extraConfig = ''
              Host *
                IdentityFile /run/agenix/demo-operator-key
                StrictHostKeyChecking no
                UserKnownHostsFile /dev/null
            '';
          })
        ];
    };

    web-01 = mkHost {
      hostName = "web-01";
      platform = "x86_64-linux";
      hostSpec = orgDefaults;
      modules =
        hostModules "web-01"
        ++ [
          impermanent
          {
            services.nixfleet-agent = {
              enable = true;
              controlPlaneUrl = "https://cp-01:8080";
              tags = ["web"];
              healthChecks.http = [
                {url = "http://localhost:80/health";}
              ];
            };
          }
        ];
    };

    web-02 = mkHost {
      hostName = "web-02";
      platform = "x86_64-linux";
      hostSpec = orgDefaults;
      modules =
        hostModules "web-02"
        ++ [
          impermanent
          {
            services.nixfleet-agent = {
              enable = true;
              controlPlaneUrl = "https://cp-01:8080";
              tags = ["web"];
              healthChecks.http = [
                {url = "http://localhost:80/health";}
              ];
            };
          }
        ];
    };

    db-01 = mkHost {
      hostName = "db-01";
      platform = "x86_64-linux";
      hostSpec = orgDefaults;
      modules =
        hostModules "db-01"
        ++ [
          scopes.backup
          {
            services.nixfleet-agent = {
              enable = true;
              controlPlaneUrl = "https://cp-01:8080";
              tags = ["db"];
            };
            nixfleet.backup = {
              enable = true;
              schedule = "*-*-* 03:00:00";
              backend = "restic";
              restic = {
                repository = "/var/lib/backup/restic-repo";
                passwordFile = "/run/agenix/restic-password";
              };
            };
          }
        ];
    };

    mon-01 = mkHost {
      hostName = "mon-01";
      platform = "x86_64-linux";
      hostSpec = orgDefaults;
      modules =
        hostModules "mon-01"
        ++ [
          {
            services.nixfleet-agent = {
              enable = true;
              controlPlaneUrl = "https://cp-01:8080";
              tags = ["monitoring"];
            };
          }
        ];
    };

    cache-01 = mkHost {
      hostName = "cache-01";
      platform = "x86_64-linux";
      hostSpec = orgDefaults;
      modules =
        hostModules "cache-01"
        ++ [
          {
            services.nixfleet-cache-server = {
              enable = true;
              openFirewall = true;
              signingKeyFile = "/run/agenix/cache-signing-key";
            };
          }
        ];
    };
  };
}
