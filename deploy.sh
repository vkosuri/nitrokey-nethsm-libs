#!/usr/bin/env bash
# Build and package the NetHSM module for this Linux host.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
if [[ $(uname -sm) != 'Linux x86_64' ]]; then
    echo 'Supported hosts: x86-64 Ubuntu 22.04, Rocky Linux 8 and CentOS 7.' >&2
    exit 2
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export RUSTUP_HOME="$work/rustup" CARGO_HOME="$work/cargo" BUILD_TMP="$work"
export DIST_DIR="$work/dist"
if [[ -z ${SOURCE_DIR:-} ]]; then
    export SOURCE_DIR="$work/nethsm-pkcs11" FETCH_SOURCE=1
fi
bash ci/build-inside.sh

# The fresh staging directory contains exactly one checked library from this run.
libs=("$DIST_DIR"/*/*.so)
[[ ${#libs[@]} == 1 && -s ${libs[0]} ]]
name=$(basename "${libs[0]}" .so)
package="$work/$name"
mkdir "$package"
cp "${libs[0]}" README.md LICENSE "$package/"
cp -r docs examples "$package/"
cp "$SOURCE_DIR/LICENSE" "$package/LICENSE-nethsm-pkcs11"
(cd "$package" && sha256sum *.so > SHA256SUMS)
mkdir -p dist
archive=$(mktemp "dist/.$name.XXXXXX")
trap 'rm -rf "$work"; rm -f "$archive"' EXIT
tar -C "$work" -czf "$archive" "$name"
mkdir "$work/check"
tar -xzf "$archive" -C "$work/check"
(cd "$work/check/$name" && sha256sum -c SHA256SUMS)
chmod 0644 "$archive"
cp -r "$DIST_DIR/"* dist/
mv -f "$archive" "dist/$name.tar.gz"
echo "Archive: $PWD/dist/$name.tar.gz"
