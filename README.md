# NetHSM PKCS#11 shared libraries

This repository packages Nitrokey's PKCS#11 module for x86-64 Linux. Choose the artifact built for your distribution. Each filename includes the upstream module version, distribution and architecture.

| Build target | Container image | Maximum glibc |
| --- | --- | --- |
| Ubuntu 22.04 | `ubuntu:22.04` | 2.35 |
| Rocky Linux 8 | `rockylinux/rockylinux:8` | 2.28 |
| CentOS 7 | `centos:7` | 2.17 |

## Build a tarball on this machine

From this repository on any x86-64 Linux target in the table, run:

```bash
bash deploy.sh
```

The script detects the OS, installs its build dependencies (using sudo when needed), downloads upstream v3.0.1 and builds against the host's glibc. On CentOS 7 it redirects the retired CentOS package repositories to the vault. Allow network access to the package repositories, GitHub and the Rust toolchain server.

The script prints the path to the verified `.tar.gz` in `dist/`. Extract it and run `sha256sum -c SHA256SUMS` inside the extracted directory. The archive contains the shared library, its checksum, configuration example, setup guide, README and both project licenses. Use the steps below to also exercise the library against a disposable NetHSM.

## Build and test

Pull requests and pushes to `main` run all three builds. To run the matrix manually, select **Actions → Build and test shared libraries → Run workflow**, or run `gh workflow run build-shared-libs.yml`. The default upstream source is `v3.0.1`. Each build uses the upstream Cargo lockfile.

To reproduce one job on an x86-64 Linux host with Docker, run these commands from the repository root. Use a fresh checkout for the source clone.

```bash
git clone --depth 1 --branch v3.0.1 https://github.com/Nitrokey/nethsm-pkcs11.git nethsm-pkcs11
bash ci/run-target.sh ubuntu:22.04
```

Substitute another image from the table to test that target. The script starts a disposable NetHSM simulator with no published port. It compiles the module inside the target OS, checks the staged library's glibc requirements, then loads that same file with `pkcs11-tool`. The test generates a 2048-bit RSA key pair, signs a message and verifies the signature with OpenSSL using the simulator's public key. It also encrypts a binary payload with OpenSSL, decrypts it through the module and compares the recovered bytes by SHA-256. Finally, it deletes the private key and confirms that a new session no longer lists it. The simulator is removed when the run exits.

Local output is under `dist/<target>/`. In Actions, download the corresponding `shared-libs-<target>` artifact. To configure the library for your own NetHSM, see the [server setup guide](docs/NETWORK-HSM-SERVER-SETUP.md) and [module configuration example](examples/p11nethsm.conf.example).

## Releases and versioning

Repository release tags use `vMAJOR.MINOR.PATCH`. The version describes the packaging contract, which covers supported targets, artifact names, archive layout and documented build commands. Increment MAJOR for an incompatible change, MINOR for compatible new functionality and PATCH for a compatible fix. An upstream module update is versioned according to its impact on consumers. Its own version remains visible in each library filename.

To publish a release, tag the reviewed commit on `main` and push the tag. For example, for an initial release candidate:

```bash
git tag -a v0.1.0-rc.1 -m "First packaging release candidate"
git push origin v0.1.0-rc.1
```

The release workflow validates the tag, runs all three key tests and publishes the ZIP, individual libraries and checksum manifest. SemVer prerelease tags create GitHub prereleases. Build metadata such as `+build.7` is accepted. Manually dispatching `release.yml` creates a downloadable bundle for inspection.

Extract the ZIP and verify its contents before installing the matching library:

```bash
unzip nethsm-pkcs11-libs-v0.1.0-rc.1.zip -d nethsm-libs
(cd nethsm-libs && sha256sum -c sha256sums.txt)
```
