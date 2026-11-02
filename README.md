# Build a Nitrokey NetHSM server lab and test it through PKCS#11

Build the Nitrokey NetHSM development server from upstream source, then use this repository's PKCS#11 harness to test it from a separate Ubuntu 22.04 x86-64 client. The lab has three server hosts: CentOS 7, Rocky Linux 8 and Ubuntu 22.04. The client loads the same Ubuntu shared library for every test. An application calls PKCS#11 locally; the module sends the operation to the selected NetHSM over HTTPS.

## 1. Build and start the server

On a dedicated lab server, clone the upstream NetHSM system software. Select the same upstream revision on all three servers and record its commit. Follow that revision's developer manual to install its OCaml, OPAM, Solo5 and host prerequisites and activate its OPAM switch. Then build and start the local development system from the upstream checkout:

```bash
git clone --recursive https://github.com/Nitrokey/nethsm.git
cd nethsm
git rev-parse HEAD
# After setting up the OPAM switch described in this checkout's developer manual:
eval "$(opam env)"
make -j"$(nproc)" build
sudo tools/setup-net-dev.sh
make run
```

The network setup command creates TAP interfaces on the server host. With upstream defaults, the development instance answers at `https://192.168.1.1/api/v1/health/state` from that host. For a three-server lab, configure a distinct client-reachable HTTPS endpoint on each host and a certificate trusted by the Ubuntu client. The harness uses the SSH hostname for HTTPS and takes the port from `NETHSM_PORT`. Set it to the actual endpoint port; the harness default is 8443.

`make run` runs in the foreground. For automated tests, the lab administrator must provide a native systemd unit named `nethsm-native.service` that starts the configured runtime. Stop the foreground run before starting the unit. This repository's `deploy.sh` builds the **client module**. The native server builds on the three host distributions have not been verified in this repository. [Nitrokey server source](https://github.com/Nitrokey/nethsm) · [Upstream local build and run instructions](https://github.com/Nitrokey/nethsm/blob/main/docs/developer-documentation.md#local-build)

## 2. Create the harness

| Step | Where | What to do |
| --- | --- | --- |
| [00 · Plan the lab](docs/00-START-HERE.md) | All hosts | Assign one Ubuntu client and a separate endpoint to each server. |
| [01 · Start and provision servers](docs/01-START-SERVERS.md) | Each server | Start the service, confirm the API reports `Operational`, and prepare an operator and a distinct RSA signing key. |
| [02 · Install the client library](docs/02-INSTALL-CLIENT.md) | Ubuntu client | Build or extract the Ubuntu module, install it at `/usr/local/lib/nitrokey/libnethsm_pkcs11.so`, and check its dependencies. |
| [03 · Configure profiles](docs/03-CONFIGURE-PROFILES.md) | Ubuntu client | Create one profile per server with its endpoint, TLS fingerprint, operator, key label and trusted public key. |
| [04 · Verify PKCS#11](docs/04-VERIFY-PKCS11.md) | Ubuntu client | Initialize the module, inspect slots and tokens, log in, sign a fresh challenge and verify the signature. |
| [05 · Run GitHub Actions](docs/05-RUN-GITHUB-ACTIONS.md) | GitHub and Ubuntu client | Register the client runner and configure each server's SSH identity, host key and port. |

## 3. Run the server tests

After completing steps 01–03, run this from **this repository's root on the Ubuntu client**:

```bash
(
  set -e
  module=/usr/local/lib/nitrokey/libnethsm_pkcs11.so
  for server in centos-7 rockylinux-8 ubuntu-22.04; do
    profile="/etc/nethsm-harness/$server"
    echo "Testing $server"
    P11NETHSM_CONFIG_FILE="$profile/p11nethsm.conf" \
      bash ci/test-remote-nethsm.sh "$module" "$profile"
  done
)
```

Expect **three `Verified OK` results**, one against each server's trusted public key. Once the workflow is on the default branch and the lab is configured, run `gh workflow run native-nethsm.yml --ref main`. The workflow builds the Ubuntu module once, starts each remote service over SSH, and performs all PKCS#11 calls from the client. [Harness script](ci/test-remote-nethsm.sh) · [GitHub Actions workflow](.github/workflows/native-nethsm.yml) · [Nitrokey PKCS#11 configuration](https://docs.nitrokey.com/nethsm/pkcs11-setup)

## Client library packages

This repository also packages Nitrokey's PKCS#11 module for applications running directly on each supported x86-64 Linux distribution.

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

Pull requests and pushes to `main` run all three builds. To run the matrix manually, select **Actions ΓåÆ Build and test shared libraries ΓåÆ Run workflow**, or run `gh workflow run build-shared-libs.yml`. The default upstream source is `v3.0.1`. Each build uses the upstream Cargo lockfile.

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
