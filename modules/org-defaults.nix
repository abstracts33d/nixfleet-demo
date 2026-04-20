# Shared organization defaults for all demo fleet hosts.
#
# orgDefaults: identity fields passed as hostSpec to mkHost.
# orgOperators: NixOS module that declares the "deploy" operator.
{
  orgDefaults = {
    timeZone = "UTC";
    locale = "en_US.UTF-8";
    keyboardLayout = "us";
  };

  orgOperators = {...}: {
    nixfleet.operators = {
      primaryUser = "deploy";
      rootSshKeys = [
        "ssh-ed25519 NixfleetDemoKeyReplaceWithYourOwn"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDUo3EKc38tQQL8lJdPUK8RsVZpruFCxIABOMT1c8qIs nixfleet-demo-operator"
      ];
      users.deploy = {
        isAdmin = true;
        sshAuthorizedKeys = [
          "ssh-ed25519 NixfleetDemoKeyReplaceWithYourOwn"
        ];
      };
    };
  };
}
