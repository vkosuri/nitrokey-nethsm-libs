# Running Nitrokey NetHSM as a Network HSM Server

Environment setup guide for the platforms this repository builds shared
libraries for: **Ubuntu 22.04 LTS**, **Rocky Linux 8** and **CentOS Linux 7**.

> **Scope.** This guide turns a general-purpose Linux server into a NetHSM
> appliance: host preparation, container runtime, service supervision,
> firewall exposure, provisioning, and the client wiring that consumes the
> shared libraries produced by the CI pipelines in
> [`.github/workflows/`](../.github/workflows/build-shared-libs.yml).
> Upstream references: [Nitrokey/nethsm](https://github.com/Nitrokey/nethsm)
> (system software), [Nitrokey/nethsm-pkcs11](https://github.com/Nitrokey/nethsm-pkcs11)
> (PKCS#11 module), [NetHSM docs](https://docs.nitrokey.com/nethsm/).

> **Not the harness lab.** This guide deploys the `nitrokey/nethsm` container
> as `nethsm.service` on host port **9443**, for applications that use the
> packaged libraries. The native three-server PKCS#11 harness instead tests the
> upstream development system started by `nethsm-native.service` from
> [`server/`](../server/), on port **8443** by default. Start with
> [00 · Set up the NetHSM lab](00-START-HERE.md) for the harness. To point the
> harness at a container host instead, name its unit `nethsm-native.service`
> and set the GitHub environment's `NETHSM_PORT` to 9443.

**Operating system guides:** [Ubuntu 22.04](os/ubuntu-22.04.md) · [Rocky Linux 8](os/rockylinux-8.md) · [CentOS 7](os/centos-7.md). OS-specific commands are only in those guides; this page covers what is the same everywhere.

**Sections:** [1 Architecture](#1-architecture-in-one-page) · [2 Prerequisites](#2-platform-prerequisites) · [3 Host preparation](#3-server-host-preparation) · [4 Run the server](#4-running-nethsm-as-a-server) · [5 Firewall](#5-opening-the-firewall) · [6 Users, keys and clients](#6-users-keys-and-the-pkcs11-clients) · [7 Persistence](#7-persistence-backup-and-upgrades) · [8 Troubleshooting](#8-troubleshooting-quick-reference) · [9 Variables](#9-variable-index)

---

## 1. Architecture in one page

```
+------------------+  +------------------+  +---------------------------+
| Linux clients    |  | Windows clients  |  | Container workloads       |
| OpenSSL / Java / |  | SunPKCS11 /      |  | .so mounted read-only,    |
| pkcs11-tool      |  | PKI Proxy        |  | config via Secret/volume  |
+--------+---------+  +--------+---------+  +------------+--------------+
         |   PKCS#11 calls (C_Login, C_Sign, C_Decrypt)        |
         +-----------------------+-----------------------------+
                                 |
                    libnethsm_pkcs11.so (Rust, rustls)
                    built per-OS by this repo's CI
                                 |  REST over TLS 1.2/1.3
                                 v
                    https://<hsm-host>:9443/api/v1
                                 |
                    +------------+------------+
                    | NetHSM container        |
                    |  internal API port 8443 |
                    |  -v /var/lib/nethsm:/data:Z
                    +------------+------------+
                                 |
                    Encrypted user data store
                    (sealed by the Unlock Passphrase)
```

Design decisions used throughout this guide:

| Decision | Choice |
| --- | --- |
| API port | host **9443/TCP** mapped to container port 8443 |
| TLS | self-signed certificate from provisioning, **pinned by SHA-256 fingerprint** on clients |
| Runtime | Docker (CE) container supervised by a systemd unit |
| Boot mode | **Attended Boot** (system comes up Locked; operator unlocks) |
| Isolation | one Operator account + one tag per application |

---

## 2. Platform prerequisites

| | Ubuntu 22.04 | Rocky Linux 8 | CentOS Linux 7 |
| --- | --- | --- | --- |
| Status | LTS (runner image deprecated in GH Actions) | maintained | **EOL since 2024-06-30** |
| glibc | 2.35 | 2.28 | 2.17 |
| Package manager | `apt` | `dnf` | `yum` (+ vault fix, §3.3) |
| Firewall | `ufw` or `firewalld` | `firewalld` | `firewalld` |
| Docker install | §3.2 | §3.3 | §3.3 |

Minimum sizing for the HSM server: 2 vCPU, 4 GB RAM, 20 GB disk, plus a
DNS A/AAAA + reverse entry for `$NETHSM_FQDN` and a synchronized clock
(`chronyd` / `systemd-timesyncd`) — the API stamps its system time at
provisioning and validates authenticated requests against it.

Keep the management tooling off the server: `nitropy` runs on an admin
workstation with **Python 3.11+** (`pynitrokey` requires ≥ 3.11):

```console
python3 -m pip install --user pipx
python3 -m pipx ensurepath
python3 -m pipx install pynitrokey
nitropy version
```

On CentOS 7 workstations install a modern interpreter first (Miniforge, uv
or pyenv) — the system Python 3.6 cannot run current pynitrokey.

---

## 3. Server host preparation

### 3.1 Service account and directories (all OSes)

```bash
groupadd --system nethsm
useradd --system --gid nethsm --home-dir /opt/nethsm --shell /sbin/nologin nethsm
mkdir -p /opt/nethsm /var/lib/nethsm
chown -R nethsm:nethsm /opt/nethsm /var/lib/nethsm
chmod 0700 /var/lib/nethsm
```

`/var/lib/nethsm` is the encrypted key store and must survive every upgrade;
`/opt/nethsm` is build scratch space and can be wiped at any time.

### 3.2 Install Docker and host packages (per operating system)

The packages, repositories and Docker installation differ for each OS. Follow section *Container-based NetHSM server* in your OS guide, then continue here:

| OS | Guide section |
| --- | --- |
| Ubuntu 22.04 | [5. Container-based NetHSM server](os/ubuntu-22.04.md#5-container-based-nethsm-server-optional) |
| Rocky Linux 8 | [4. Container-based NetHSM server](os/rockylinux-8.md#4-container-based-nethsm-server-optional) |
| CentOS 7 | [4. Container-based NetHSM server](os/centos-7.md#4-container-based-nethsm-server-optional) (vault repositories, Docker 26.1.4) |

### 3.3 Container runtime sanity (all OSes)

```bash
docker info | head -5
xfs_info / 2>/dev/null | grep -o 'ftype=1' || echo "check backing fs d_type"
```

---

## 4. Running NetHSM as a server

### 4.1 Start the container

Use the official production image, or an image built from source per the
upstream developer documentation (`Nitrokey/nethsm`, Route A container
build). The container always listens on **8443** internally:

```bash
docker run -d --name nethsm \
  -p 9443:8443 \
  -v /var/lib/nethsm:/data:Z \
  nitrokey/nethsm:prod      # or your locally built tag, e.g. nethsm:local
docker ps --filter name=nethsm
curl -sk https://127.0.0.1:9443/api/v1/health/state
# expect: {"state":"Unprovisioned"}
```

`:Z` lets the container runtime relabel the bind mount for SELinux
(enforcing mode stays on — nothing here requires disabling it).

### 4.2 Systemd supervision

`/etc/systemd/system/nethsm.service` (works identically on the three OSes —
systemd 219 on CentOS 7 understands all of it):

```ini
[Unit]
Description=NetHSM container service
Requires=docker.service
After=docker.service

[Service]
Restart=always
ExecStart=/usr/bin/docker run --rm --name nethsm -p 9443:8443 \
  -v /var/lib/nethsm:/data:Z nitrokey/nethsm:prod
ExecStop=/usr/bin/docker stop -t 10 nethsm

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable --now nethsm.service
```

### 4.3 Provision (once)

From the admin workstation (Python 3.11+ with `nitropy`):

```bash
export NETHSM_HOST=hsm01.example.org:9443
nitropy nethsm --host $NETHSM_HOST --no-verify-tls provision
# prompts: Unlock Passphrase (x2), Admin Passphrase (x2)
```

Provisioning stamps the system time and generates the **self-signed API
certificate**. Export it and record the fingerprint — every client pins it:

```bash
nitropy nethsm --host $NETHSM_HOST --no-verify-tls get-certificate --api > nethsm-api.pem
openssl x509 -in nethsm-api.pem -noout -fingerprint -sha256
```

Then rehearse the state machine: `state` → `lock` → `state` (Locked) →
`unlock` → `state` (Operational). With Attended Boot, every reboot leaves
the system Locked until an operator supplies the Unlock Passphrase.

The three passphrases are not recoverable if lost. Store Admin / Unlock /
Backup passphrases in **separate** escrows; the Backup Passphrase is set
once via `nitropy nethsm --host $NETHSM_HOST set-backup-passphrase`.

---

## 5. Opening the firewall

Open host port 9443 only to the application subnets. The commands are in your OS guide: `ufw` on [Ubuntu 22.04](os/ubuntu-22.04.md#34-firewall), `firewalld` on [Rocky Linux 8](os/rockylinux-8.md#24-firewall) and [CentOS 7](os/centos-7.md#24-firewall). Those examples use the harness port 8443; use 9443 for the container deployment.

**Docker bypass warning.** Published container ports are forwarded through
the Docker iptables chains and *bypass the INPUT rules* of firewalld/ufw.
Always verify from a real client, and put source filters that must apply to
container traffic into the **DOCKER-USER** chain (firewalld hosts) or bind
publication to the service IP (`-p $NETHSM_IP:9443:8443`).

Verification from any client host:

```bash
openssl s_client -connect $NETHSM_FQDN:9443 </dev/null 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256     # must match the recorded pin
curl -sk https://$NETHSM_FQDN:9443/api/v1/health/state
```

---

## 6. Users, keys and the PKCS#11 clients

### 6.1 Accounts and tags

```bash
nitropy nethsm --host $NETHSM_HOST add-user \
  --user-id app-alpha --real-name "Application Alpha" --role Operator
nitropy nethsm --host $NETHSM_HOST generate-key \
  --type RSA --length 2048 \
  --mechanism RSA_Signature_PSS_SHA256 \
  --key-id app-alpha-key-01
nitropy nethsm --host $NETHSM_HOST add-user-tag app-alpha app-alpha
nitropy nethsm --host $NETHSM_HOST add-key-tag app-alpha-key-01 app-alpha
```

One Operator account + one tag per application; an Operator can only use
keys sharing one of its tags. Roles available: Administrator, Operator,
Metrics, Backup, Unlock.

### 6.2 Install the CI-built shared libraries

Each OS needs its own build of the module. Its glibc ceiling is 2.35 on Ubuntu 22.04, 2.28 on Rocky Linux 8 and 2.17 on CentOS 7. Install it with the script or the manual steps in your OS guide:

| OS | One command | Guide section |
| --- | --- | --- |
| Ubuntu 22.04 | `bash deploy/ubuntu-22.04/install-client.sh` | [4. Client module](os/ubuntu-22.04.md#4-client-module) |
| Rocky Linux 8 | `bash deploy/rockylinux-8/install-client.sh` | [3. Client module](os/rockylinux-8.md#3-client-module) |
| CentOS 7 | `bash deploy/centos-7/install-client.sh` | [3. Client module](os/centos-7.md#3-client-module) |

Upstream release binaries are built on modern CI images and may need glibc symbols newer than CentOS 7's 2.17. This repository builds on each target OS to avoid that.

### 6.3 Module configuration

`/etc/nitrokey/p11nethsm.conf` (chmod 0600), identical on all OSes:

```yaml
log_level: Info
slots:
  - label: LocalHSM
    description: Corporate NetHSM
    operator:
      username: "app-alpha"
      password: "env:APP_ALPHA_PASS"
    instances:
      - url: "https://hsm01.example.org:9443/api/v1"
        max_idle_connections: 10
        sha256_fingerprints:
          - "AA:BB:CC:...:FF"        # openssl x509 -fingerprint -sha256
        retries:
          count: 3
          delay_seconds: 1
        timeout_seconds: 10
```

Never enable `danger_insecure_cert` for a production NetHSM — the
fingerprint pin *is* the TLS trust anchor here.

End-to-end proof from a client:

```bash
export APP_ALPHA_PASS='********'   # pkcs11-tool comes from the opensc package on every OS
pkcs11-tool --module /usr/local/lib/nitrokey/libnethsm_pkcs11.so --list-slots
pkcs11-tool --module /usr/local/lib/nitrokey/libnethsm_pkcs11.so \
  --login --pin env:APP_ALPHA_PASS --list-mechanisms   # keeps the PIN out of ps
```

Windows clients use the DLL + the same YAML via `P11NETHSM_CONFIG_FILE`;
JVM clients use the SunPKCS11 provider pointed at the same library.

---

## 7. Persistence, backup and upgrades

Keys survive restarts, upgrades and host rebuilds through four layers:

1. **Encrypted data volume** — `/var/lib/nethsm` bind-mounted at `/data`.
   Never delete it during upgrades; copying it raw between systems is not
   a supported migration path.
2. **Version-continuous upgrades** — move along the release line, never
   skip versions; keep the previous image tag for rollback by editing the
   systemd unit. Record the git commit/image digest you built from.
3. **Encrypted system backup** — portable artifact of the whole key store:
   ```bash
   nitropy nethsm --host $NETHSM_HOST --user backup-user --no-verify-tls \
     backup /srv/backups/nethsm-$(date +%F).bin
   ```
   Copy off-site, test restores quarterly on a scratch instance.
4. **Migration runbook** — new host or new release: inventory source →
   final backup → provision target → restore → re-verify TLS fingerprint →
   end-to-end PKCS#11 test from an unrelated client → decommission old.

Losing the Unlock Passphrase means the data store cannot be opened again.

---

## 8. Troubleshooting quick reference

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `state` = Locked after reboot | Attended Boot working as designed | `nitropy ... unlock` |
| PKCS#11 slot has no token | NetHSM not Operational | Unlock or provision; check state |
| TLS cert error on client | Certificate replaced; stale pin | Re-export, update `sha256_fingerprints` |
| Connection refused | Container down / mapping / firewall | `docker ps`, `ss -lntp`, firewall rules |
| `GLIBC_2.xx not found` on load | Wrong artifact for the OS | Use the per-OS build; run `ci/check-glibc-compat.sh` |
| HTTP 403 from API | Operator missing the key's tag | Align `add-user-tag` / `add-key-tag` |
| HTTP 401 from API | Passphrase / `env:` variable wrong | Check credentials and env of the service user |
| yum fails on CentOS 7 | mirrorlist retired | Vault repositories: [CentOS 7 guide](os/centos-7.md#23-install-by-hand) |

---

## 9. Variable index

| Placeholder | Meaning | Example |
| --- | --- | --- |
| `$NETHSM_HOST` | REST API address and port | `hsm01.example.org:9443` |
| `$NETHSM_FQDN` | DNS name of the HSM server | `hsm01.example.org` |
| Admin Passphrase | built-in admin superuser | long random string |
| Unlock Passphrase | derives the key-sealing Unlock Key | separate long string |
| Backup Passphrase | encrypts system backup files | third long string |
| `app-alpha` | per-application Operator account | `app-alpha` |
