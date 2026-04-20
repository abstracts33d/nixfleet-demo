let
  # Bootstrap age identity for demo setup.
  # In production: never commit this key. Use SSH host keys after first boot.
  demoKey = "age1evy0vu7rznp0s7zavdxe88ajjcpwk0xlmaennmkqcrt5xsn3sypqsxuhc8";

  allRecipients = [demoKey];
in {
  "root-password.age".publicKeys = allRecipients;
  "fleet-ca.age".publicKeys = allRecipients;
  # fleet-ca.pem is a public cert - committed as plain .pem, not encrypted
  "cp-cert.age".publicKeys = allRecipients;
  "cp-key.age".publicKeys = allRecipients;
  "agents/web-01-cert.age".publicKeys = allRecipients;
  "agents/web-01-key.age".publicKeys = allRecipients;
  "agents/web-02-cert.age".publicKeys = allRecipients;
  "agents/web-02-key.age".publicKeys = allRecipients;
  "agents/db-01-cert.age".publicKeys = allRecipients;
  "agents/db-01-key.age".publicKeys = allRecipients;
  "agents/mon-01-cert.age".publicKeys = allRecipients;
  "agents/mon-01-key.age".publicKeys = allRecipients;
  "cache-signing-key.age".publicKeys = allRecipients;
  "restic-password.age".publicKeys = allRecipients;
  "demo-operator-key.age".publicKeys = allRecipients;
}
