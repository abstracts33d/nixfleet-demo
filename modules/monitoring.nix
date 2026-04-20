# Monitoring - Prometheus server on mon-01 via monitoring-server scope.
# Node exporter on all hosts is handled by the o11y scope (fleet-wide).
{
  config,
  lib,
  ...
}:
lib.mkIf (config.networking.hostName == "mon-01") {
  nixfleet.monitoring.server = {
    enable = true;
    openFirewall = true;
    alerts.controlPlane = true;
    targets = [
      "cp-01:9100"
      "web-01:9100"
      "web-02:9100"
      "db-01:9100"
      "mon-01:9100"
      "cache-01:9100"
    ];
    extraScrapeConfigs = [
      {
        job_name = "nixfleet-cp";
        scheme = "https";
        tls_config = {
          ca_file = "/etc/nixfleet/fleet-ca.pem";
          cert_file = "/run/agenix/agent-mon-01-cert";
          key_file = "/run/agenix/agent-mon-01-key";
        };
        static_configs = [{targets = ["cp-01:8080"];}];
      }
    ];
  };
}
