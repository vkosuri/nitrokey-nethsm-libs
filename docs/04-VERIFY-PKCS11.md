# 04 · Prove that each server handles PKCS#11 operations

Run these commands on Ubuntu from the harness repository root. The application calls the local shared library. The library connects to the configured NetHSM HTTPS port and requests operations on the operator's keys. The server's native service exposes that HTTPS endpoint; it needs no separate raw PKCS#11 listener.

```bash
module=/usr/local/lib/nitrokey/libnethsm_pkcs11.so
profile=/etc/nethsm-harness/centos-7
export P11NETHSM_CONFIG_FILE="$profile/p11nethsm.conf"
pkcs11-tool --module "$module" --show-info
pkcs11-tool --module "$module" --list-slots
pkcs11-tool --module "$module" --token-label "$(cat "$profile/token-label")" --list-mechanisms
```

Look for the configured token and an RSA signing mechanism. Slot/token information is the PKCS#11 view available to the application. A list of administrative namespaces is a separate NetHSM operation.

Run the full proof against all three servers. Set the configuration for **each invocation** so a prior export cannot select the wrong server:

```bash
for target in centos-7 rockylinux-8 ubuntu-22.04; do
  profile=/etc/nethsm-harness/$target
  echo "Testing $target"
  P11NETHSM_CONFIG_FILE="$profile/p11nethsm.conf" \
    bash ci/test-remote-nethsm.sh "$module" "$profile" || break
done
```

Expect three distinct `Verified OK` results, each followed by two `Rejected as expected` lines and the harness PASS line. Each run:

- requires a slot whose token label matches `token-label`, and requires that token to offer `SHA256-RSA-PKCS`;
- logs in, signs fresh random bytes and verifies the signature with that server's trusted public key;
- repeats the signature with a random wrong PIN, then with the configuration's pinned certificate fingerprint replaced by zeros. Both must fail, and a timeout counts as a failure.

The script refuses a configuration that does not contain the fingerprint from `certificate-sha256` or that sets `danger_insecure_cert: true`. A TCP connection or successful slot listing alone does not exercise the signing key.

| Failure | Check first |
| --- | --- |
| Module cannot load | Architecture, Ubuntu artifact path and `ldd` output from step 02 |
| Connection refused or timed out | DNS, HTTPS port, firewall, server bind address and service state |
| TLS verification fails | Server-specific certificate fingerprint from step 03 |
| Login or key lookup fails | Operator PIN, namespace, tags, token label and PKCS#11 key label |
| `wrong PIN … was accepted` | Whether the configuration file sets an operator password that the module uses instead of the PIN passed to `C_Login`; remove it |
| `does not match the pinned fingerprint was accepted` | Another configuration file the module merges disables certificate checks; use a dedicated client account |
| Signature verification fails | Whether this profile contains the public key from this exact server and key pair |

Next: [05 · Run in GitHub Actions](05-RUN-GITHUB-ACTIONS.md).
