# Changelog

This project uses Semantic Versioning for its packaging and harness releases.
The upstream NetHSM PKCS#11 module version is recorded separately in library filenames.

## Unreleased

### Added

- Build and package Nitrokey's PKCS#11 module (default upstream version 3.0.1) for x86-64 Ubuntu 22.04, Rocky Linux 8 and CentOS 7. Each build checks the library's required glibc version against the target distribution.
- Generate an RSA key in a disposable NetHSM, verify a signature, decrypt a binary payload and check key deletion through each target's compiled module.
- Run `bash deploy.sh` to build on a supported host and create a tarball with the library, checksum, configuration example, licenses and setup guides.
- Run a native harness from one Ubuntu 22.04 client against three separately provisioned NetHSM server hosts. The workflow checks service startup, slot and token information, operator login and a signature from each server.
- Follow the [numbered lab runbook](docs/00-START-HERE.md) to prepare servers, install the Ubuntu client library and configure the harness.
- Package tested libraries and checksums for GitHub Releases using SemVer tags, including release candidates.
