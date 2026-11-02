# 02 · Install the Ubuntu client module

Run on the **Ubuntu 22.04 x86-64 client**, from the harness repository root. Use its Ubuntu library for all three servers. The CentOS and Rocky binaries are for applications running on those operating systems.

```bash
. /etc/os-release
echo "$PRETTY_NAME $(uname -m)"
sudo apt-get update
sudo apt-get install -y opensc openssl ca-certificates curl python3 openssh-client
```

**Shortcut:** `bash deploy/ubuntu-22.04/install-client.sh` runs every step on this page and installs the module at the path used below. Use the manual steps to understand or customise the process.

`opensc` supplies `pkcs11-tool`. OpenSSL verifies signatures. APT installs the tools' system dependencies. Install the NetHSM provider itself using one of these paths:

**Build on this client** using a clean checkout:

```bash
bash deploy.sh
ls dist/ubuntu-22.04/*.so
module=$(realpath dist/ubuntu-22.04/*.so)
```

**Or use the Ubuntu tarball.** Set the exact filename, extract it in a new directory and check the manifest before selecting its library:

```bash
archive=/path/to/nethsm-pkcs11-3.0.1-ubuntu-22.04-x86_64-glibc.tar.gz
stage=$(mktemp -d)
tar -xzf "$archive" -C "$stage"
(cd "$stage/$(basename "$archive" .tar.gz)" && sha256sum -c SHA256SUMS)
module=$(realpath "$stage"/*/*.so)
```

After either path, give applications a stable module path:

```bash
sudo install -D -m 0755 "$module" /usr/local/lib/nitrokey/libnethsm_pkcs11.so
ldd /usr/local/lib/nitrokey/libnethsm_pkcs11.so
command -v pkcs11-tool openssl
```

Every dynamic dependency reported by `ldd` should resolve. If one says `not found`, install its Ubuntu package before testing. Keep Ubuntu's system glibc in place. The harness passes the absolute module path, so a system-wide PKCS#11 registration is optional.

Next: [03 · Configure server profiles](03-CONFIGURE-PROFILES.md).
