# Changelog

This project uses Semantic Versioning for its packaging and harness releases.
The upstream NetHSM PKCS#11 module version is recorded separately in library filenames.

## Unreleased

### Added

- Build and package Nitrokey's PKCS#11 module (default upstream version 3.0.1) for x86-64 Ubuntu 22.04, Rocky Linux 8 and CentOS 7. Each build checks the library's required glibc version against the target distribution.
- Generate an RSA key in a disposable NetHSM, verify a signature, decrypt a binary payload and check key deletion through each target's compiled module.
- Run `bash deploy.sh` to build on a supported host and create a tarball with the library, checksum, configuration example, licenses and setup guides.
- Run a native harness from one Ubuntu 22.04 client against three separately provisioned NetHSM server hosts. The workflow checks service startup, waits for each API to report `Operational` behind its pinned TLS certificate, and requires the configured token and `SHA256-RSA-PKCS` mechanism. It then requires an operator login and a verified signature from each server. Signing must also fail with a wrong PIN and with a wrong certificate fingerprint.
- Install the native lab service on each server with `server/install-native-unit.sh`. The script installs `nethsm-native.service`, which runs the upstream development system, forwards its HTTPS API to a client-reachable port, and restricts the harness SSH account's sudo rights to starting it.
- Follow the [numbered lab runbook](docs/00-START-HERE.md) to prepare servers, install the Ubuntu client library and configure the harness.
- Package tested libraries and checksums for GitHub Releases using SemVer tags, including release candidates.
