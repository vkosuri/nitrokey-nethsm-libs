# One Ubuntu client, three NetHSM servers

Use one dedicated Ubuntu 22.04 x86-64 machine as the application client and GitHub Actions runner. Give only this runner the custom label `nethsm-ubuntu22-client`. The workflow builds the Ubuntu PKCS#11 module once and uses that artifact for all three connections.

| Remote server OS | GitHub environment | Client configuration directory |
| --- | --- | --- |
| CentOS 7 | `nethsm-centos-7` | `/etc/nethsm-harness/centos-7` |
| Rocky Linux 8 | `nethsm-rockylinux-8` | `/etc/nethsm-harness/rockylinux-8` |
| Ubuntu 22.04 | `nethsm-ubuntu-22.04` | `/etc/nethsm-harness/ubuntu-22.04` |

## Prepare the servers

Each server must already have a working native NetHSM runtime, a systemd unit named `nethsm-native.service`, and a provisioned test operator and RSA PKCS#1 signing key. Use a different test key per server. Arrange for each service to reach Operational state after startup or unlock it through your normal lab procedure. The server software and native unit are lab prerequisites. The repository builds the client module. Its Docker-based service example is unsuitable for this harness.

Allow the lab SSH account to start only the native unit using noninteractive sudo. The Ubuntu client must reach each server's SSH service and NetHSM HTTPS port using the same hostname. The workflow checks the remote OS before starting the unit, leaves the service running, and performs all PKCS#11 operations on the Ubuntu client.

## Prepare the client and GitHub

1. Give the Ubuntu runner the prerequisites for `bash deploy.sh`, including noninteractive package installation. Install Python 3 and the OpenSSH client. Configure the runner account with no unrelated PKCS#11 slots.
2. In each configuration directory listed above, create these one-line files: `operator-user`, `operator-pin`, `token-label`, `key-label`, and `certificate-sha256` (the server certificate fingerprint verified out of band). Also install the trusted RSA public key as `public.pem`. Protect each directory with mode 0700 and the PIN with 0600. The PIN remains on the Ubuntu client.
3. In each GitHub environment set `SSH_TARGET` (variable, `user@server`), `NETHSM_PORT` (variable, default 8443), and secrets `SSH_KEY` and `SSH_KNOWN_HOSTS`. Use the independently verified SSH host key. Restrict the environments to the default branch.
4. Once the workflow is on the default branch, run `gh workflow run native-nethsm.yml --ref main`.

## Passing result

Each matrix job checks systemd status and TCP connectivity, loads the same Ubuntu module, initializes PKCS#11, enumerates slots and tokens, selects the token, lists mechanisms, logs in, and signs a fresh challenge. OpenSSL must report `Verified OK` with that server's pinned public key. Slot/token information is the PKCS#11 view of the operator's configured partition. The test does not enumerate every administrative namespace.
