#!/usr/bin/env bash
set -euo pipefail
source /etc/os-release
case "$ID:${VERSION_ID%%.*}" in
    ubuntu:22)
        [[ $VERSION_ID == 22.04 ]]
        target=ubuntu-22.04; glibc=2.35
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y build-essential cmake ca-certificates curl opensc openssl perl
        ;;
    rocky:8)
        target=rockylinux-8; glibc=2.28
        dnf -y install gcc gcc-c++ make cmake perl curl opensc openssl
        ;;
    centos:7)
        target=centos-7; glibc=2.17
        vault_repos() {
            sed -Ei -e 's|^mirrorlist=|#mirrorlist=|' \
                -e 's@^#baseurl=https?://mirror\.centos\.org/centos/(\$releasever|7)@baseurl=https://vault.centos.org/7.9.2009@' \
                /etc/yum.repos.d/CentOS-*.repo
        }
        vault_repos
        yum -y install centos-release-scl
        vault_repos
        yum -y install devtoolset-11-gcc-c++ make perl curl opensc openssl
        export PATH="/opt/rh/devtoolset-11/root/usr/bin:$PATH"
        # CentOS 7 ships CMake 2.8. Install Kitware's glibc-compatible binary.
        curl -fsSL -o /tmp/cmake.tar.gz https://github.com/Kitware/CMake/releases/download/v3.28.6/cmake-3.28.6-linux-x86_64.tar.gz
        tar -xzf /tmp/cmake.tar.gz -C /tmp
        export PATH="/tmp/cmake-3.28.6-linux-x86_64/bin:$PATH"
        ;;
    *) echo "Unsupported target: $ID $VERSION_ID" >&2; exit 2 ;;
esac

source_dir=${SOURCE_DIR:-nethsm-pkcs11}
dist=${DIST_DIR:-dist}
curl -fsSL -o /tmp/rustup-init \
    https://static.rust-lang.org/rustup/archive/1.27.1/x86_64-unknown-linux-gnu/rustup-init
chmod +x /tmp/rustup-init
/tmp/rustup-init -y --profile minimal --no-modify-path --default-toolchain "${RUST_VERSION:-1.95.0}"
export PATH="$HOME/.cargo/bin:$PATH"
manifest="$source_dir/Cargo.toml"
export CARGO_TARGET_DIR="$source_dir/target/$target"
cargo build --manifest-path "$manifest" --package nethsm_pkcs11 --release --locked
pkgid=$(cargo pkgid --manifest-path "$manifest" -p nethsm_pkcs11)
version=${pkgid##*#}
version=${version##*@}
artifact="$dist/$target/nethsm-pkcs11-$version-$target-x86_64-glibc.so"
mkdir -p "$dist/$target"
cp "$CARGO_TARGET_DIR/release/libnethsm_pkcs11.so" "$artifact"
bash ci/check-glibc-compat.sh "$artifact" "$glibc"
if [[ ${TEST_KEY:-0} == 1 ]]; then
    bash ci/test-key.sh "$artifact"
fi
