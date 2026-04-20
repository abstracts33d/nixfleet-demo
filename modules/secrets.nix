# Agenix secret management - decryption identity, root password, fleet CA trust.
# Called from fleet.nix with the agenix NixOS module.
agenixModule: {
  config,
  lib,
  ...
}: let
  hostName = config.networking.hostName;
in {
  imports = [agenixModule];

  nixfleet.secrets.enable = true;

  # Bootstrap: demo age identity deployed to all hosts for first-boot decryption.
  # In production: remove this after adding host SSH keys to recipients.nix.
  age.identityPaths =
    config.nixfleet.secrets.resolvedIdentityPaths
    ++ ["/etc/nixfleet-demo/age-identity.txt"];

  environment.etc."nixfleet-demo/age-identity.txt" = {
    source = ../secrets/age-identity.txt;
    mode = "0400";
  };

  # Agenix activation must run AFTER etc activation deploys the identity key.
  # Without this, agenix runs before the file exists and decryption fails on first boot.
  system.activationScripts.agenixInstall.deps = ["etc"];

  # Root password (hashed, encrypted)
  age.secrets.root-password.file = ../secrets/root-password.age;
  users.users.root.hashedPasswordFile = config.age.secrets.root-password.path;

  # Deploy operator also gets the root password for demo convenience
  nixfleet.operators.users.deploy.hashedPasswordFile = config.age.secrets.root-password.path;

  # Fleet CA - plain .pem (public cert, no encryption needed).
  # Added to system trust store at build time for agent TLS verification.
  security.pki.certificateFiles = [../secrets/fleet-ca.pem];

  # Also deploy to /etc for CP's tls.clientCa at runtime
  environment.etc."nixfleet/fleet-ca.pem".source = ../secrets/fleet-ca.pem;

  # Cache signing key (cache-01 only).
  # Owner must be harmonia - the cache server runs as that user.
  age.secrets.cache-signing-key = lib.mkIf (hostName == "cache-01") {
    file = ../secrets/cache-signing-key.age;
    owner = "harmonia";
  };

  # Restic backup password (db-01 only)
  age.secrets.restic-password = lib.mkIf (hostName == "db-01") {
    file = ../secrets/restic-password.age;
    owner = "root";
  };

  # Demo operator SSH key - deployed to cp-01 for pushing to cache and SSH deploys.
  # Authorized on all hosts via orgOperators.
  age.secrets.demo-operator-key = lib.mkIf (hostName == "cp-01") {
    file = ../secrets/demo-operator-key.age;
    owner = "root";
    mode = "0400";
  };
}
