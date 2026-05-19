# Security Policy

## Demo Credentials - Not Vulnerabilities

This demo fleet ships with pre-baked credentials for zero-setup local testing. These are **intentional** and documented in the README:

- `secrets/age-identity.txt` - demo-only age private key
- `secrets/*.age` - encrypted secrets using the demo key
- `secrets/fleet-ca.age` / `fleet-ca.pem` - demo CA for mTLS
- Root password: `demo`

If you fork this repo for production use, rotate all credentials.

## Reporting Actual Vulnerabilities

For issues in this demo beyond the intentional credentials, see the [NixFleet Security Policy](https://github.com/arcanesys/nixfleet/blob/main/SECURITY.md).

For demo-specific issues, email security@arcanesys.fr.
