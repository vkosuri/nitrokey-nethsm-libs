# Deployment scripts by operating system

Each supported OS has its own folder with the same three scripts. Run them from a checkout of this repository on the machine you are setting up, or run them on remote machines from your workstation with [`remote.sh`](#remote-machines-deploy-over-ssh). Every script checks that it runs on its folder's OS, and `-h` prints its settings.

| Folder | Server: build and install | Server: start or restart | Client: install the PKCS#11 module |
| --- | --- | --- | --- |
| [`ubuntu-22.04/`](ubuntu-22.04/) | [`install-server.sh`](ubuntu-22.04/install-server.sh) | [`start-server.sh`](ubuntu-22.04/start-server.sh) | [`install-client.sh`](ubuntu-22.04/install-client.sh) |
| [`rockylinux-8/`](rockylinux-8/) | [`install-server.sh`](rockylinux-8/install-server.sh) | [`start-server.sh`](rockylinux-8/start-server.sh) | [`install-client.sh`](rockylinux-8/install-client.sh) |
| [`centos-7/`](centos-7/) | [`install-server.sh`](centos-7/install-server.sh) | [`start-server.sh`](centos-7/start-server.sh) | [`install-client.sh`](centos-7/install-client.sh) |

The OS folders contain only package lists and OS-specific preparation, such as the CentOS 7 vault repositories and GCC 11. The shared steps live in [`common/`](common/). To support another OS, copy a folder and change its package commands and `require_os` line.

## Remote machines: deploy over SSH

Run [`remote.sh`](remote.sh) on your workstation or the harness client. It needs only `ssh`, `tar` and this checkout locally. For each host, it detects the OS, copies the checkout to `~/nethsm-libs` and runs the matching script there:

```bash
bash deploy/remote.sh detect admin@hsm-centos7.lab admin@hsm-rocky8.lab admin@hsm-ubuntu22.lab
bash deploy/remote.sh server -e NETHSM_REF=v5.0 -e SSH_ACCOUNT=labrunner \
  admin@hsm-centos7.lab admin@hsm-rocky8.lab admin@hsm-ubuntu22.lab
bash deploy/remote.sh start -e RESTART=1 admin@hsm-rocky8.lab
bash deploy/remote.sh client -e CLIENT_TARBALL=dist/nethsm-pkcs11-3.0.1-centos-7-x86_64-glibc.tar.gz admin@app01.example.org
```

| Action | Runs on each host |
| --- | --- |
| `detect` | Prints the OS and the matching folder; changes nothing |
| `server` | `deploy/<os>/install-server.sh` |
| `start` | `deploy/<os>/start-server.sh` (`-e RESTART=1` adds `--restart`) |
| `client` | `deploy/<os>/install-client.sh`. A local `CLIENT_TARBALL` file is uploaded first |

Pass settings with `-e VAR=value`. Hosts are processed one after another, a failed host does not stop the others, and the run ends with a summary. Any failure makes the exit status non-zero. SSH uses your own configuration and host-key checks. The remote account needs sudo; in a terminal you are prompted for a sudo password if the host asks for one. Set `REMOTE_DIR` to copy somewhere other than `~/nethsm-libs`.

## Server: build, install and start

On each lab server, as root or with sudo:

```bash
sudo NETHSM_REF=<upstream tag or commit> SSH_ACCOUNT=labrunner bash deploy/rockylinux-8/install-server.sh
```

The script:

1. installs build tools, `socat` and the libraries the upstream build needs;
2. creates the `nethsm` build account under `/opt/nethsm` and installs `opam`;
3. clones [Nitrokey/nethsm](https://github.com/Nitrokey/nethsm) at `NETHSM_REF` and prints the exact commit;
4. creates an OPAM switch and runs the upstream build;
5. installs `nethsm-native.service` with [`server/install-native-unit.sh`](../server/install-native-unit.sh), writes `/etc/nethsm-native/nethsm-native.env`, and limits `SSH_ACCOUNT`'s sudo rights to starting the unit;
6. starts the service and reports whether the API is `Operational`, `Locked` or `Unprovisioned`.

Rerunning updates the checkout to `NETHSM_REF`, rebuilds and regenerates the settings file. After a reboot or a configuration change:

```bash
bash deploy/rockylinux-8/start-server.sh            # or --restart
```

| Setting | Default | Purpose |
| --- | --- | --- |
| `NETHSM_REF` | `main` | Upstream tag or commit. Use the same value on all three servers |
| `SSH_ACCOUNT` | *(none)* | Harness SSH login allowed to run `sudo systemctl start nethsm-native.service` |
| `NETHSM_LISTEN_PORT` | `8443` | Client-reachable HTTPS port. Must match the GitHub environment's `NETHSM_PORT` |
| `NETHSM_UPSTREAM` | `192.168.1.1:443` | Address of the development instance behind the forward |
| `NETHSM_BUILD_CMD` | `make -j$(nproc) build` | Upstream build command |
| `NETHSM_RUN_CMD` | `make run` | Command the service runs |
| `NETHSM_OCAML` | `4.14.4` | OCaml version for the `nethsm` OPAM switch, as in upstream's manual |
| `NETHSM_OPAM_REPO` | `git+https://github.com/ocaml/opam-repository` | opam repository for the switch. Pin a known-good commit with `#<commit>` |
| `NETHSM_USER`, `NETHSM_HOME` | `nethsm`, `/opt/nethsm` | Build account and its home |
| `NETHSM_RUN_USER` | `NETHSM_USER` | Account that runs `make run`. Set `root` if your revision needs it for TAP or KVM |
| `OPAM_VERSION`, `OPAM_SHA256` | `2.2.1`, *(none)* | opam binary to install, and an optional checksum to enforce |
| `SKIP_BUILD`, `NO_START` | `0` | Set to `1` to skip the build or the service start |

> **Not yet verified end to end.** The OS preparation, account, opam setup, checkout, unit installation and settings file are tested in containers. The upstream build and `make run` need the host prerequisites from that revision's [developer manual](https://github.com/Nitrokey/nethsm/blob/main/docs/developer-documentation.md#local-build). If the build fails, follow the manual and rerun with `NETHSM_BUILD_CMD` set. Running the instance needs TAP networking and, for upstream's default Solo5/hvt target, read-write access to `/dev/kvm` for `NETHSM_RUN_USER`. Containers provide neither.

## Client: install the PKCS#11 module

On any machine whose applications load the module, including the Ubuntu harness client:

```bash
bash deploy/ubuntu-22.04/install-client.sh
```

The script installs `pkcs11-tool` and OpenSSL. It builds the module for this OS with [`deploy.sh`](../deploy.sh), including the glibc compatibility gate, and installs it at `/usr/local/lib/nitrokey/libnethsm_pkcs11.so`. It then checks that all dependencies resolve. On Ubuntu it also installs `python3` and the OpenSSH client for the harness role.

| Setting | Default | Purpose |
| --- | --- | --- |
| `CLIENT_TARBALL` | *(build from source)* | Install from a `nethsm-pkcs11-*-<os>-*.tar.gz` after checking its `SHA256SUMS` |
| `CLIENT_LIB` | `/usr/local/lib/nitrokey/libnethsm_pkcs11.so` | Install location |

Then configure the module ([section 6.3](../docs/NETWORK-HSM-SERVER-SETUP.md#63-module-configuration)) or, on the harness client, [create the server profiles](../docs/03-CONFIGURE-PROFILES.md).

Complete per-OS guides: [Ubuntu 22.04](../docs/os/ubuntu-22.04.md) · [Rocky Linux 8](../docs/os/rockylinux-8.md) · [CentOS 7](../docs/os/centos-7.md)
