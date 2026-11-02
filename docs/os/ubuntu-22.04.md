# NetHSM on Ubuntu 22.04

This guide covers everything for **Ubuntu 22.04 x86-64** and nothing for other systems. An Ubuntu machine can be the **harness client** (one machine tests all three servers), a **native lab server** (harness target `ubuntu-22.04`), a **client** whose applications load the PKCS#11 module, or a **container host** for a production-style NetHSM.

Other systems: [Rocky Linux 8](rockylinux-8.md) · [CentOS 7](centos-7.md) · [Lab overview](../00-START-HERE.md)

| At a glance | Ubuntu 22.04 |
| --- | --- |
| Scripts | [`deploy/ubuntu-22.04/`](../../deploy/ubuntu-22.04/) |
| Package manager · firewall | `apt` · `ufw` |
| glibc | 2.35 |
| Harness target · GitHub environment | `ubuntu-22.04` · `nethsm-ubuntu-22.04` |
| Profile directory on the harness client | `/etc/nethsm-harness/ubuntu-22.04` |
| Module file | `nethsm-pkcs11-<version>-ubuntu-22.04-x86_64-glibc.so` |

## Contents

1. [Quick start](#1-quick-start)
2. [Harness client and Actions runner](#2-harness-client-and-actions-runner)
3. [Native lab server](#3-native-lab-server)
   - [3.1 Requirements](#31-requirements) · [3.2 Install with the script](#32-install-with-the-script) · [3.3 Install by hand](#33-install-by-hand) · [3.4 Firewall](#34-firewall) · [3.5 Provision and create the signing key](#35-provision-and-create-the-signing-key) · [3.6 Operate the service](#36-operate-the-service) · [3.7 Connect it to the harness](#37-connect-it-to-the-harness)
4. [Client module](#4-client-module)
   - [4.1 Install with the script](#41-install-with-the-script) · [4.2 Install by hand](#42-install-by-hand) · [4.3 Configure](#43-configure) · [4.4 Verify](#44-verify)
5. [Container-based NetHSM server (optional)](#5-container-based-nethsm-server-optional)
6. [Troubleshooting](#6-troubleshooting)

## 1. Quick start

From a checkout of this repository **on the Ubuntu machine**:

```bash
sudo NETHSM_REF=v5.0 SSH_ACCOUNT=labrunner bash deploy/ubuntu-22.04/install-server.sh   # lab server
bash deploy/ubuntu-22.04/install-client.sh                                              # client module and harness tools
```

Or **from your workstation** over SSH. The script detects each host's OS, so one command can set up all three lab servers:

```bash
bash deploy/remote.sh detect admin@hsm-centos7.lab admin@hsm-rocky8.lab admin@hsm-ubuntu22.lab
bash deploy/remote.sh server -e NETHSM_REF=v5.0 -e SSH_ACCOUNT=labrunner \
  admin@hsm-centos7.lab admin@hsm-rocky8.lab admin@hsm-ubuntu22.lab
bash deploy/remote.sh client admin@harness-client.lab
```

All settings are listed in [deploy/README.md](../../deploy/README.md).

## 2. Harness client and Actions runner

Exactly one Ubuntu 22.04 machine plays this role. It builds the module once and uses that same file to test the CentOS 7, Rocky Linux 8 and Ubuntu 22.04 servers.

1. Install the module and tools: `bash deploy/ubuntu-22.04/install-client.sh`. It also installs `python3` and the OpenSSH client. Manual steps: [02 · Install the client](../02-INSTALL-CLIENT.md).
2. Create one profile per server, with endpoint, TLS fingerprint, operator PIN, key label and public key: [03 · Configure profiles](../03-CONFIGURE-PROFILES.md).
3. Verify each server by hand: [04 · Verify PKCS#11](../04-VERIFY-PKCS11.md).
4. Register this machine as the self-hosted runner `nethsm-ubuntu22-client` and create the three GitHub environments: [05 · Run GitHub Actions](../05-RUN-GITHUB-ACTIONS.md).
5. Read what a passing run looks like: [harness reference](../NATIVE-PKCS11-HARNESS.md#passing-result).

## 3. Native lab server

### 3.1 Requirements

- Ubuntu 22.04 on x86-64, with sudo access.
- `/dev/kvm` available. Upstream's default Solo5/hvt target runs the NetHSM as a KVM guest, so use bare metal or a VM with nested virtualization.
- Outbound HTTPS to GitHub (upstream source, opam repository and OCaml).
- Use the same upstream revision (`NETHSM_REF`) on all three lab servers.

### 3.2 Install with the script

```bash
sudo NETHSM_REF=v5.0 SSH_ACCOUNT=labrunner bash deploy/ubuntu-22.04/install-server.sh
```

It installs the build packages with `apt`, creates the `nethsm` account under `/opt/nethsm`, installs opam, clones upstream at `NETHSM_REF`, builds it with OCaml 4.14.4, then installs and starts `nethsm-native.service`. It finishes by reporting whether the API is `Operational`, `Locked` or `Unprovisioned`. Rerun it to upgrade or repair. Set `SKIP_BUILD=1` or `NO_START=1` to skip those steps.

### 3.3 Install by hand

Each step matches what the script does, so you can follow or debug it:

```bash
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential m4 pkg-config git curl \
    ca-certificates rsync patch unzip bzip2 libgmp-dev socat iproute2 sudo
sudo useradd --system --create-home --home-dir /opt/nethsm --shell /bin/bash nethsm
curl -fsSLo opam https://github.com/ocaml/opam/releases/download/2.2.1/opam-2.2.1-x86_64-linux
sudo install -m 0755 opam /usr/local/bin/opam
sudo -iu nethsm bash -c '
  set -e
  export OPAMROOT=/opt/nethsm/opam OPAMYES=1 OPAMASSUMEDEPEXTS=1
  git clone --recursive https://github.com/Nitrokey/nethsm.git src && cd src && git checkout v5.0
  opam init --bare --disable-sandboxing --no-setup nethsm-default git+https://github.com/ocaml/opam-repository
  opam switch create nethsm 4.14.4 --repos nethsm-default
  eval "$(opam env --switch=nethsm)"
  make -j"$(nproc)" build'
sudo bash server/install-native-unit.sh labrunner
sudoedit /etc/nethsm-native/nethsm-native.env   # NETHSM_SRC=/opt/nethsm/src, NETHSM_RUN_USER, OPAMROOT=/opt/nethsm/opam, OPAMSWITCH=nethsm
sudo systemctl start nethsm-native.service
```

The unit runs upstream's `tools/setup-net-dev.sh` (TAP interfaces) and `make run`. `socat` forwards port 8443 to the instance at `192.168.1.1:443` without terminating TLS. [Unit](../../server/nethsm-native.service) · [run wrapper](../../server/nethsm-native-run.sh) · [settings](../../server/nethsm-native.env.example)

### 3.4 Firewall

Allow the HTTPS port only from the harness client, or from your application subnet:

```bash
sudo ufw allow from 10.20.30.15 to any port 8443 proto tcp
sudo ufw status verbose
```

### 3.5 Provision and create the signing key

Check the state on the server (`bash deploy/ubuntu-22.04/start-server.sh` prints it), then provision or unlock from an admin workstation that has `nitropy`. It needs Python 3.11+, so install it with `pipx install pynitrokey` on a newer system. Record the certificate fingerprint, because the client pins it:

```bash
HOST=hsm-ubuntu22.lab:8443
nitropy nethsm --host "$HOST" --no-verify-tls provision            # first time only
nitropy nethsm --host "$HOST" --no-verify-tls get-certificate --api > server-tls.pem
openssl x509 -in server-tls.pem -noout -fingerprint -sha256
nitropy nethsm --host "$HOST" add-user --real-name "Harness operator" --role Operator --user-id harnessop
nitropy nethsm --host "$HOST" generate-key --type RSA --length 2048 --mechanism RSA_Signature_PKCS1 --key-id harnessrsa
nitropy nethsm --host "$HOST" get-key harnessrsa --public-key > public.pem
```

Use a key pair that no other server shares. Give `server-tls.pem`, `public.pem` and the operator credentials to the harness client administrator. More detail: [01 · Start each NetHSM server](../01-START-SERVERS.md).

### 3.6 Operate the service

```bash
bash deploy/ubuntu-22.04/start-server.sh             # start and report state
bash deploy/ubuntu-22.04/start-server.sh --restart   # after changing /etc/nethsm-native/nethsm-native.env
systemctl status nethsm-native.service
sudo journalctl -u nethsm-native.service -n 60
```

An instance that comes up `Locked` must be unlocked (`nitropy nethsm --host "$HOST" unlock`) before the harness can sign.

### 3.7 Connect it to the harness

On the harness client, create the `ubuntu-22.04` profile ([03 · profiles](../03-CONFIGURE-PROFILES.md)) and verify it ([04 · verify](../04-VERIFY-PKCS11.md)). In GitHub, create the `nethsm-ubuntu-22.04` environment with `SSH_TARGET=labrunner@hsm-ubuntu22.lab` and `NETHSM_PORT=8443` ([05 · Actions](../05-RUN-GITHUB-ACTIONS.md)).

## 4. Client module

### 4.1 Install with the script

```bash
bash deploy/ubuntu-22.04/install-client.sh                                  # build from source
CLIENT_TARBALL=nethsm-pkcs11-3.0.1-ubuntu-22.04-x86_64-glibc.tar.gz \
  bash deploy/ubuntu-22.04/install-client.sh                                # or a release tarball
```

The module is installed at `/usr/local/lib/nitrokey/libnethsm_pkcs11.so`.

### 4.2 Install by hand

```bash
sudo apt-get install -y opensc openssl ca-certificates curl tar python3 openssh-client
bash deploy.sh                                          # builds dist/ubuntu-22.04/*.so and checks glibc <= 2.35
sudo install -D -m 0755 dist/ubuntu-22.04/*.so /usr/local/lib/nitrokey/libnethsm_pkcs11.so
ldd /usr/local/lib/nitrokey/libnethsm_pkcs11.so | grep 'not found' || echo 'all dependencies resolve'
```

### 4.3 Configure

Create `/etc/nitrokey/p11nethsm.conf` with mode 0600, or point `P11NETHSM_CONFIG_FILE` at another file:

```yaml
slots:
  - label: LocalHSM
    operator:
      username: "app-alpha"
    instances:
      - url: "https://hsm-ubuntu22.lab:8443/api/v1"
        sha256_fingerprints:
          - "AA:BB:...:FF"     # openssl x509 -in server-tls.pem -noout -fingerprint -sha256
```

Never set `danger_insecure_cert: true`; the fingerprint is the trust anchor. All options: [annotated example](../../examples/p11nethsm.conf.example). The harness client uses one profile per server instead; see [03 · Configure profiles](../03-CONFIGURE-PROFILES.md).

### 4.4 Verify

```bash
module=/usr/local/lib/nitrokey/libnethsm_pkcs11.so
pkcs11-tool --module "$module" --list-slots
read -rsp 'Operator PIN: ' PIN; echo; export PIN
pkcs11-tool --module "$module" --login --pin env:PIN --list-objects
```

## 5. Container-based NetHSM server (optional)

This is a production-style deployment of the `nitrokey/nethsm` image on port 9443. It is not the native harness lab.

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu jammy stable" |
  sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io
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
ExecStart=/usr/bin/docker run --rm --name nethsm -p 9443:8443 -v /var/lib/nethsm:/data nitrokey/nethsm:prod
ExecStop=/usr/bin/docker stop -t 10 nethsm

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload && sudo systemctl enable --now nethsm.service
curl -sk https://127.0.0.1:9443/api/v1/health/state     # {"state":"Unprovisioned"}
```

Published Docker ports bypass `ufw` rules. Publish on one address (`-p 10.0.0.5:9443:8443`), or filter in the `DOCKER-USER` chain. Provisioning, users, backups and upgrades are the same on every OS: [server setup guide](../NETWORK-HSM-SERVER-SETUP.md#43-provision-once).

## 6. Troubleshooting

| Symptom | Fix |
| --- | --- |
| A deploy script says the host is not Ubuntu 22.04 | Use the folder for the host's OS, or `deploy/remote.sh`, which picks it for you |
| `pkcs11-tool: unrecognized option` for `env:` PINs | Use Ubuntu 22.04's `opensc` (0.22) or newer |
| `/dev/kvm` permission denied | Add `NETHSM_RUN_USER` to the `kvm` group, or set `NETHSM_RUN_USER=root` |
| The service starts but no TAP device appears | Check `journalctl -u nethsm-native.service`. `setup-net-dev.sh` needs root, which the unit has |
| The client cannot connect to port 8443 | `sudo ufw status`, `ss -lntp | grep 8443`, and check that `socat` is running in the service |
| The harness job fails with `reports Locked` | Unlock the server; the harness never unlocks it automatically |
| The harness job fails on a certificate fingerprint | The server certificate changed. Update `certificate-sha256` in that profile |
| The state stays `Locked` | Unlock with `nitropy nethsm --host HOST:8443 unlock` |
