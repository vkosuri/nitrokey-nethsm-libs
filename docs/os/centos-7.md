# NetHSM on CentOS 7

This guide covers everything for **CentOS 7 x86-64** and nothing for other systems. A CentOS 7 machine can be a **native lab server** (harness target `centos-7`), a **client** whose applications load the PKCS#11 module, or a **container host** for a production-style NetHSM. The harness client itself is always Ubuntu; see the [Ubuntu 22.04 guide](ubuntu-22.04.md).

> **End of life.** CentOS 7 stopped receiving updates on 2024-06-30. Packages come from the frozen vault archive, which gets no security fixes. Limit each host's network exposure to the client subnets.

Other systems: [Ubuntu 22.04](ubuntu-22.04.md) · [Rocky Linux 8](rockylinux-8.md) · [Lab overview](../00-START-HERE.md)

| At a glance | CentOS 7 |
| --- | --- |
| Scripts | [`deploy/centos-7/`](../../deploy/centos-7/) |
| Package manager · firewall | `yum` from `vault.centos.org` · `firewalld` |
| Compiler | GCC 4.8 in base; the scripts use devtoolset-11 (GCC 11) |
| glibc · systemd | 2.17 · 219 (the provided units only use directives it supports) |
| Harness target · GitHub environment | `centos-7` · `nethsm-centos-7` |
| Profile directory on the Ubuntu harness client | `/etc/nethsm-harness/centos-7` |
| Module file | `nethsm-pkcs11-<version>-centos-7-x86_64-glibc.so` |

## Contents

1. [Quick start](#1-quick-start)
2. [Native lab server](#2-native-lab-server)
   - [2.1 Requirements](#21-requirements) · [2.2 Install with the script](#22-install-with-the-script) · [2.3 Install by hand](#23-install-by-hand) · [2.4 Firewall](#24-firewall) · [2.5 Provision and create the signing key](#25-provision-and-create-the-signing-key) · [2.6 Operate the service](#26-operate-the-service) · [2.7 Connect it to the harness](#27-connect-it-to-the-harness)
3. [Client module](#3-client-module)
   - [3.1 Install with the script](#31-install-with-the-script) · [3.2 Install by hand](#32-install-by-hand) · [3.3 Configure](#33-configure) · [3.4 Verify](#34-verify)
4. [Container-based NetHSM server (optional)](#4-container-based-nethsm-server-optional)
5. [Troubleshooting](#5-troubleshooting)

## 1. Quick start

From a checkout of this repository **on the CentOS 7 machine**:

```bash
sudo NETHSM_REF=v5.0 SSH_ACCOUNT=labrunner bash deploy/centos-7/install-server.sh   # lab server
bash deploy/centos-7/install-client.sh                                              # client module
```

Or **from your workstation** over SSH. The script detects CentOS 7 and runs the same scripts there:

```bash
bash deploy/remote.sh server -e NETHSM_REF=v5.0 -e SSH_ACCOUNT=labrunner admin@hsm-centos7.lab
bash deploy/remote.sh client admin@app01.example.org
```

All settings are listed in [deploy/README.md](../../deploy/README.md).

## 2. Native lab server

### 2.1 Requirements

- CentOS 7 on x86-64, with sudo access. A host with an F5 BIG-IP-style prompt (`[root@host:Active:Standalone]`) is a sealed appliance, not a general-purpose server; do not use it.
- `/dev/kvm` available. Upstream's default Solo5/hvt target runs the NetHSM as a KVM guest.
- Outbound HTTPS to `vault.centos.org` and GitHub.
- Use the same upstream revision (`NETHSM_REF`) on all three lab servers.
- **Not yet verified:** the upstream NetHSM build has not been tested on CentOS 7. The script provides GCC 11, but upstream dependencies may need newer system libraries.

### 2.2 Install with the script

```bash
sudo NETHSM_REF=v5.0 SSH_ACCOUNT=labrunner bash deploy/centos-7/install-server.sh
```

It points yum at the vault archive and installs devtoolset-11 and the build packages. It then creates the `nethsm` account under `/opt/nethsm`, installs opam, clones upstream at `NETHSM_REF`, builds it with OCaml 4.14.4, and installs and starts `nethsm-native.service`. It finishes by reporting whether the API is `Operational`, `Locked` or `Unprovisioned`. Rerun it to upgrade or repair. Set `SKIP_BUILD=1` or `NO_START=1` to skip those steps.

### 2.3 Install by hand

Each step matches what the script does, so you can follow or debug it:

```bash
# 1. Vault repositories (mirrorlist.centos.org no longer exists)
sudo sed -Ei -e 's|^mirrorlist=|#mirrorlist=|' \
  -e 's@^#baseurl=https?://mirror\.centos\.org/centos/(\$releasever|7)@baseurl=https://vault.centos.org/7.9.2009@' \
  /etc/yum.repos.d/CentOS-*.repo
# 2. GCC 11 from Software Collections (repeat the sed: the SCL release adds repo files)
sudo yum -y install centos-release-scl
sudo sed -Ei -e 's|^mirrorlist=|#mirrorlist=|' \
  -e 's@^#baseurl=https?://mirror\.centos\.org/centos/(\$releasever|7)@baseurl=https://vault.centos.org/7.9.2009@' \
  /etc/yum.repos.d/CentOS-*.repo
sudo yum -y --disablerepo=centos-sclo-sclo \
  --setopt='centos-sclo-rh.baseurl=https://vault.centos.org/7.9.2009/sclo/$basearch/rh/' \
  install devtoolset-11-gcc devtoolset-11-gcc-c++ devtoolset-11-make
# 3. Build and runtime packages
sudo yum -y install gcc gcc-c++ make m4 pkgconfig git git-daemon curl rsync patch \
  unzip bzip2 gmp-devel socat iproute tar sudo util-linux which
# 4. Account, opam, upstream build
sudo useradd --system --create-home --home-dir /opt/nethsm --shell /bin/bash nethsm
curl -fsSLo opam https://github.com/ocaml/opam/releases/download/2.2.1/opam-2.2.1-x86_64-linux
sudo install -m 0755 opam /usr/local/bin/opam
sudo -iu nethsm bash -c '
  set -e
  export PATH=/opt/rh/devtoolset-11/root/usr/bin:$PATH OPAMROOT=/opt/nethsm/opam OPAMYES=1 OPAMASSUMEDEPEXTS=1
  git clone --recursive https://github.com/Nitrokey/nethsm.git src && cd src && git checkout v5.0
  opam init --bare --disable-sandboxing --no-setup nethsm-default git+https://github.com/ocaml/opam-repository
  opam switch create nethsm 4.14.4 --repos nethsm-default
  eval "$(opam env --switch=nethsm)"
  make -j"$(nproc)" build'
# 5. Service
sudo bash server/install-native-unit.sh labrunner
sudoedit /etc/nethsm-native/nethsm-native.env   # NETHSM_SRC=/opt/nethsm/src, NETHSM_RUN_USER, OPAMROOT=/opt/nethsm/opam, OPAMSWITCH=nethsm
sudo systemctl start nethsm-native.service
```

The unit runs upstream's `tools/setup-net-dev.sh` (TAP interfaces) and `make run`. `socat` forwards port 8443 to the instance at `192.168.1.1:443` without terminating TLS. [Unit](../../server/nethsm-native.service) · [run wrapper](../../server/nethsm-native-run.sh) · [settings](../../server/nethsm-native.env.example)

### 2.4 Firewall

Allow the HTTPS port only from the Ubuntu harness client, or from your application subnet:

```bash
sudo systemctl enable --now firewalld
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.20.30.15/32" port port="8443" protocol="tcp" accept'
sudo firewall-cmd --reload
sudo firewall-cmd --list-rich-rules
```

### 2.5 Provision and create the signing key

Check the state on the server (`bash deploy/centos-7/start-server.sh` prints it). Then provision or unlock from an admin workstation that has `nitropy`. It needs Python 3.11+, so not CentOS 7's Python 3.6. Record the certificate fingerprint, because the client pins it:

```bash
HOST=hsm-centos7.lab:8443
nitropy nethsm --host "$HOST" --no-verify-tls provision            # first time only
nitropy nethsm --host "$HOST" --no-verify-tls get-certificate --api > server-tls.pem
openssl x509 -in server-tls.pem -noout -fingerprint -sha256
nitropy nethsm --host "$HOST" add-user --real-name "Harness operator" --role Operator --user-id harnessop
nitropy nethsm --host "$HOST" generate-key --type RSA --length 2048 --mechanism RSA_Signature_PKCS1 --key-id harnessrsa
nitropy nethsm --host "$HOST" get-key harnessrsa --public-key > public.pem
```

Use a key pair that no other server shares. Give `server-tls.pem`, `public.pem` and the operator credentials to the harness client administrator. More detail: [01 · Start each NetHSM server](../01-START-SERVERS.md).

### 2.6 Operate the service

```bash
bash deploy/centos-7/start-server.sh             # start and report state
bash deploy/centos-7/start-server.sh --restart   # after changing /etc/nethsm-native/nethsm-native.env
systemctl status nethsm-native.service
sudo journalctl -u nethsm-native.service -n 60
```

An instance that comes up `Locked` must be unlocked (`nitropy nethsm --host "$HOST" unlock`) before the harness can sign.

### 2.7 Connect it to the harness

On the Ubuntu harness client, create the `centos-7` profile ([03 · profiles](../03-CONFIGURE-PROFILES.md)) and verify it ([04 · verify](../04-VERIFY-PKCS11.md)). In GitHub, create the `nethsm-centos-7` environment with `SSH_TARGET=labrunner@hsm-centos7.lab` and `NETHSM_PORT=8443` ([05 · Actions](../05-RUN-GITHUB-ACTIONS.md)).

## 3. Client module

### 3.1 Install with the script

```bash
bash deploy/centos-7/install-client.sh                                  # build from source
CLIENT_TARBALL=nethsm-pkcs11-3.0.1-centos-7-x86_64-glibc.tar.gz \
  bash deploy/centos-7/install-client.sh                                # or a release tarball
```

The module is installed at `/usr/local/lib/nitrokey/libnethsm_pkcs11.so`. Building from source uses the vault repositories, devtoolset-11 and a prebuilt CMake 3.28, because CentOS 7 ships CMake 2.8.

### 3.2 Install by hand

```bash
sudo yum -y install opensc openssl curl tar             # after the vault sed in 2.3
bash deploy.sh                                          # builds dist/centos-7/*.so and checks glibc <= 2.17
sudo install -D -m 0755 dist/centos-7/*.so /usr/local/lib/nitrokey/libnethsm_pkcs11.so
ldd /usr/local/lib/nitrokey/libnethsm_pkcs11.so | grep 'not found' || echo 'all dependencies resolve'
```

Only the `centos-7` build loads on this OS. Upstream release binaries and the Rocky or Ubuntu builds need newer glibc and fail with `GLIBC_2.xx not found`.

### 3.3 Configure

Create `/etc/nitrokey/p11nethsm.conf` with mode 0600, or point `P11NETHSM_CONFIG_FILE` at another file:

```yaml
slots:
  - label: LocalHSM
    operator:
      username: "app-alpha"
    instances:
      - url: "https://hsm-centos7.lab:8443/api/v1"
        sha256_fingerprints:
          - "AA:BB:...:FF"     # openssl x509 -in server-tls.pem -noout -fingerprint -sha256
```

Never set `danger_insecure_cert: true`; the fingerprint is the trust anchor. All options: [annotated example](../../examples/p11nethsm.conf.example).

### 3.4 Verify

```bash
module=/usr/local/lib/nitrokey/libnethsm_pkcs11.so
pkcs11-tool --module "$module" --list-slots
read -rsp 'Operator PIN: ' PIN; echo; export PIN
pkcs11-tool --module "$module" --login --pin env:PIN --list-objects
```

If your OpenSC version does not accept `env:PIN`, upgrade it or use an application that calls `C_Login` itself. Avoid putting the PIN on the command line.

## 4. Container-based NetHSM server (optional)

This is a production-style deployment of the `nitrokey/nethsm` image on port 9443. It is not the native harness lab. Docker 26.1.4 is the last engine release for EL7.

```bash
# after the vault sed in 2.3
sudo yum -y install yum-utils device-mapper-persistent-data lvm2 firewalld chrony
sudo systemctl enable --now firewalld chronyd
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum -y install docker-ce docker-ce-cli containerd.io
sudo systemctl enable --now docker
sudo mkdir -p /var/lib/nethsm && sudo chmod 0700 /var/lib/nethsm
```

Create `/etc/systemd/system/nethsm.service`:

```ini
[Unit]
Description=NetHSM container service
Requires=docker.service
After=docker.service

[Service]
Restart=always
ExecStart=/usr/bin/docker run --rm --name nethsm -p 9443:8443 -v /var/lib/nethsm:/data:Z nitrokey/nethsm:prod
ExecStop=/usr/bin/docker stop -t 10 nethsm

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload && sudo systemctl enable --now nethsm.service
curl -sk https://127.0.0.1:9443/api/v1/health/state     # {"state":"Unprovisioned"}
```

Published Docker ports bypass `firewalld` INPUT rules. Restrict them in the `DOCKER-USER` chain, or publish on one address (`-p 10.0.0.5:9443:8443`). Provisioning, users, backups and upgrades are the same on every OS: [server setup guide](../NETWORK-HSM-SERVER-SETUP.md#43-provision-once).

## 5. Troubleshooting

| Symptom | Fix |
| --- | --- |
| `Could not resolve host: mirrorlist.centos.org` | Apply the vault `sed` from 2.3. The scripts do this themselves |
| `centos-sclo-*` repository errors | Repeat the vault `sed` after installing `centos-release-scl` (2.3, step 2) |
| A deploy script says the host is not CentOS 7 | Use the folder for the host's OS, or `deploy/remote.sh`, which picks it for you |
| OCaml or C dependency fails to compile | Check that `gcc --version` reports 11 inside the build (devtoolset-11 on `PATH`), then compare with the upstream developer manual |
| `git-daemon` missing during `make run` | `sudo yum -y install git-daemon` |
| `/dev/kvm` permission denied | Add `NETHSM_RUN_USER` to the `kvm` group, or set `NETHSM_RUN_USER=root` |
| `GLIBC_2.xx not found` when loading the module | Install the `centos-7` build. Its glibc ceiling is 2.17 |
| The client cannot connect to port 8443 | `firewall-cmd --list-rich-rules`, `ss -lntp | grep 8443`, and check that `socat` is running in the service |
| The state stays `Locked` | Unlock with `nitropy nethsm --host HOST:8443 unlock` |
