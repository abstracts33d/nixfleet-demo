# TLS/mTLS - wires agenix-decrypted certs to CP and agent services.
{
  config,
  lib,
  ...
}: let
  hostName = config.networking.hostName;
in {
  # CP server TLS + mTLS client verification
  services.nixfleet-control-plane = lib.mkIf config.services.nixfleet-control-plane.enable {
    tls = {
      cert = config.age.secrets.cp-cert.path;
      key = config.age.secrets.cp-key.path;
      clientCa = "/etc/nixfleet/fleet-ca.pem";
    };
  };

  # Agent client cert for mTLS
  services.nixfleet-agent = lib.mkIf config.services.nixfleet-agent.enable {
    tls = {
      clientCert = config.age.secrets."agent-${hostName}-cert".path;
      clientKey = config.age.secrets."agent-${hostName}-key".path;
    };
  };

  # Declare age secrets conditionally
  age.secrets = lib.mkMerge [
    (lib.mkIf config.services.nixfleet-control-plane.enable {
      cp-cert.file = ../secrets/cp-cert.age;
      cp-key.file = ../secrets/cp-key.age;
    })
    (lib.mkIf config.services.nixfleet-agent.enable {
      "agent-${hostName}-cert".file = ../secrets/agents + "/${hostName}-cert.age";
      "agent-${hostName}-key".file = ../secrets/agents + "/${hostName}-key.age";
    })
  ];
}
