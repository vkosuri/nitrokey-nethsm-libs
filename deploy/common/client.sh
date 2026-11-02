# install_client TARGET: build (or unpack) the PKCS#11 module for this OS and
# install it at a stable path. Called by deploy/<os>/install-client.sh after
# the OS-specific tool packages are installed.
# shellcheck shell=bash
install_client() {
    local target=$1 tarball=${CLIENT_TARBALL:-} dest=${CLIENT_LIB:-/usr/local/lib/nitrokey/libnethsm_pkcs11.so}
    local module stage

    if [[ -n $tarball ]]; then
        log "Unpacking $tarball"
        [[ -s $tarball ]] || die "CLIENT_TARBALL=$tarball not found"
        [[ $(basename "$tarball") == *"-$target-"* ]] || die "$tarball is not a $target build"
        stage=$(mktemp -d)
        tar -xzf "$tarball" -C "$stage"
        (cd "$stage"/*/ && sha256sum -c SHA256SUMS)
        module=$(echo "$stage"/*/*.so)
    else
        log "Building the module for $target with deploy.sh (takes a few minutes)"
        (cd "$repo_root" && bash deploy.sh)
        local built=("$repo_root/dist/$target"/*.so)
        [[ ${#built[@]} == 1 && -s ${built[0]} ]] || die "expected one library in dist/$target"
        module=${built[0]}
    fi

    log "Installing $dest"
    as_root install -D -m 0755 "$module" "$dest"
    if ldd "$dest" | grep -q 'not found'; then
        ldd "$dest" >&2
        die "unresolved dependencies in $dest"
    fi
    command -v pkcs11-tool >/dev/null || die 'pkcs11-tool missing (opensc package)'
    pkcs11-tool --module "$dest" --show-info >/dev/null 2>&1 ||
        echo "Note: pkcs11-tool --show-info failed; this is expected until a module configuration exists."
    echo "Installed $(basename "$module") as $dest"
    cat <<NEXT

Next steps:
  * Configuration: copy examples/p11nethsm.conf.example to /etc/nitrokey/p11nethsm.conf (mode 0600)
    and set your NetHSM URL, certificate fingerprint and operator. See docs/NETWORK-HSM-SERVER-SETUP.md section 6.3.
  * Harness client (Ubuntu only): continue with docs/03-CONFIGURE-PROFILES.md.
NEXT
}
