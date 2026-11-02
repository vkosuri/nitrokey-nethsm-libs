# NetHSM maintainer workflows

Use these procedures from the repository root. Choose the row that matches the requested outcome.

| Task | Entry point | Evidence to collect |
| --- | --- | --- |
| Build a client for a target OS | [deploy.sh](deploy.sh) | Required glibc version, target ceiling and archive checksum result |
| Test a packaged module on a disposable NetHSM | [Build workflow](.github/workflows/build-shared-libs.yml) | RSA signature verification, decryption round trip and key deletion for each target |
| Test three native NetHSM servers from Ubuntu | [Native workflow](.github/workflows/native-nethsm.yml) | Expected remote OS and active service, followed by a verified signature for each server |
| Prepare a versioned release | [Release workflow](.github/workflows/release.yml) | Valid tag, tested artifacts, checksums and matching changelog entry |

## Build and package a client module

Run `bash deploy.sh` on the target x86-64 Linux distribution. Inspect the archive under `dist/`. Check that its library names the correct upstream version and target. Extract it and run `sha256sum -c SHA256SUMS` inside the extracted package directory.

The glibc ceilings are 2.17 for CentOS 7, 2.28 for Rocky Linux 8 and 2.35 for Ubuntu 22.04. If a library exceeds its ceiling, inspect the build environment and dependencies. Rebuild for the affected target and repeat the gate. [Compatibility check](ci/check-glibc-compat.sh)

## Exercise the disposable simulator

Run `gh workflow run build-shared-libs.yml --ref main` once that workflow is on the default branch. For local reproduction, use the upstream checkout and target-image command in the [README](README.md). The simulator test provisions a fresh instance with test credentials. It is unsuitable for a shared server. [Test implementation](ci/test-key.sh)

## Exercise the native server lab

Use the [client profile guide](docs/03-CONFIGURE-PROFILES.md) to prepare each server's operator, token label, trusted TLS fingerprint and expected RSA public key. From the configured Ubuntu client, test one server with:

```bash
profile=/etc/nethsm-harness/centos-7
P11NETHSM_CONFIG_FILE="$profile/p11nethsm.conf" \
  bash ci/test-remote-nethsm.sh /usr/local/lib/nitrokey/libnethsm_pkcs11.so "$profile"
```

For all three servers, use `gh workflow run native-nethsm.yml --ref main` after completing [runner setup](docs/05-RUN-GITHUB-ACTIONS.md). Check each job for `Verified OK` against that server's public key. If discovery passes and signing fails, check the selected token, operator access, key label and signing mechanism; if the signature fails verification, confirm the profile contains the public key from that server.

## Prepare a release

Treat the packaging version and the upstream module version separately. Choose the SemVer change based on consumer impact. Before tagging, move the relevant changelog entries into a dated release section, validate the proposed tag with `python3 ci/check-release-tag.py vX.Y.Z` (substitute the actual version), and follow the [release instructions](README.md#releases-and-versioning). Pushing the tag publishes the release; do that only when a release is requested.
