# install_server: build the upstream NetHSM development system as a service
# account, install nethsm-native.service and (unless NO_START=1) start it.
# Called by deploy/<os>/install-server.sh after the OS-specific packages.
# shellcheck shell=bash
NETHSM_REPO=${NETHSM_REPO:-https://github.com/Nitrokey/nethsm.git}
NETHSM_REF=${NETHSM_REF:-main}
NETHSM_USER=${NETHSM_USER:-nethsm}
NETHSM_HOME=${NETHSM_HOME:-/opt/nethsm}
NETHSM_SRC=${NETHSM_SRC:-$NETHSM_HOME/src}
NETHSM_OPAMROOT=${NETHSM_OPAMROOT:-$NETHSM_HOME/opam}
NETHSM_OCAML=${NETHSM_OCAML:-4.14.4}
# Upstream's developer manual builds against opam-repository from GitHub.
NETHSM_OPAM_REPO=${NETHSM_OPAM_REPO:-git+https://github.com/ocaml/opam-repository}
NETHSM_BUILD_CMD=${NETHSM_BUILD_CMD:-make -j$(nproc) build}
NETHSM_LISTEN_PORT=${NETHSM_LISTEN_PORT:-8443}
OPAM_VERSION=${OPAM_VERSION:-2.2.1}

# as_service CMD...: run a shell command as the build account with the OPAM root.
as_service() {
    # OPAMASSUMEDEPEXTS: system packages come from deploy/<os>/, not from opam as root.
    local env=(HOME="$NETHSM_HOME" OPAMROOT="$NETHSM_OPAMROOT" OPAMYES=1 OPAMASSUMEDEPEXTS=1 PATH="$PATH")
    # Start in the build account's home: the caller's directory (often a mode
    # 0750 home directory) may not be readable by that account.
    local cmd="cd '$NETHSM_HOME' && $1"
    if [[ $NETHSM_USER == root ]]; then env "${env[@]}" bash -c "$cmd"
    else as_root runuser -u "$NETHSM_USER" -- env "${env[@]}" bash -c "$cmd"; fi
}

install_opam() {
    if command -v opam >/dev/null; then echo "Using $(command -v opam) $(opam --version)"; return; fi
    log "Installing opam $OPAM_VERSION (static binary)"
    local tmp; tmp=$(mktemp)
    curl -fsSL -o "$tmp" "https://github.com/ocaml/opam/releases/download/$OPAM_VERSION/opam-$OPAM_VERSION-x86_64-linux"
    if [[ -n ${OPAM_SHA256:-} ]]; then
        echo "$OPAM_SHA256  $tmp" | sha256sum -c - || die 'opam checksum mismatch'
    fi
    as_root install -m 0755 "$tmp" /usr/local/bin/opam
    rm -f "$tmp"
}

install_server() {
    [[ $NETHSM_REF != main ]] ||
        echo "Note: building upstream 'main'. Set NETHSM_REF to the same tag or commit on all three servers."

    log "Creating build account $NETHSM_USER ($NETHSM_HOME)"
    if [[ $NETHSM_USER != root ]] && ! id "$NETHSM_USER" >/dev/null 2>&1; then
        as_root useradd --system --create-home --home-dir "$NETHSM_HOME" --shell /bin/bash "$NETHSM_USER"
    fi
    as_root install -d -o "$NETHSM_USER" -g "$(id -gn "$NETHSM_USER")" "$NETHSM_HOME"

    install_opam

    log "Fetching $NETHSM_REPO at $NETHSM_REF into $NETHSM_SRC"
    as_service "set -e
        [ -d '$NETHSM_SRC/.git' ] || git clone --recursive '$NETHSM_REPO' '$NETHSM_SRC'
        cd '$NETHSM_SRC'
        git fetch --tags origin
        git checkout --quiet '$NETHSM_REF'
        git submodule update --init --recursive
        echo \"Upstream commit: \$(git rev-parse HEAD)\""

    log "Preparing OPAM root and OCaml $NETHSM_OCAML (first run takes a while)"
    as_service "set -e
        [ -f '$NETHSM_OPAMROOT/config' ] ||
            opam init --bare --disable-sandboxing --no-setup nethsm-default '$NETHSM_OPAM_REPO'
        opam switch list --short | grep -qx nethsm ||
            opam switch create nethsm '$NETHSM_OCAML' --repos nethsm-default"

    if [[ ${SKIP_BUILD:-0} == 1 ]]; then
        echo 'SKIP_BUILD=1: not running the upstream build.'
    else
        log "Building upstream: $NETHSM_BUILD_CMD"
        echo "If this fails, follow the developer manual of this upstream revision and rerun with NETHSM_BUILD_CMD set."
        as_service "set -e; cd '$NETHSM_SRC'; eval \"\$(opam env --switch=nethsm)\"; $NETHSM_BUILD_CMD"
    fi

    log 'Writing service settings'
    local envfile=/etc/nethsm-native/nethsm-native.env
    as_root install -d -m 0755 /etc/nethsm-native
    as_root tee "$envfile" >/dev/null <<ENV
# Written by deploy/$(basename "$(dirname "$0")")/install-server.sh on $(date -u +%F). Rerun the script to regenerate.
NETHSM_SRC=$NETHSM_SRC
NETHSM_RUN_USER=${NETHSM_RUN_USER:-$NETHSM_USER}
OPAMROOT=$NETHSM_OPAMROOT
OPAMSWITCH=nethsm
HOME=$NETHSM_HOME
NETHSM_RUN_CMD=${NETHSM_RUN_CMD:-make run}
NETHSM_SETUP_NET=${NETHSM_SETUP_NET:-1}
NETHSM_LISTEN_PORT=$NETHSM_LISTEN_PORT
NETHSM_UPSTREAM=${NETHSM_UPSTREAM:-192.168.1.1:443}
ENV
    as_root chmod 0644 "$envfile"
    echo "Wrote $envfile"
    log 'Installing nethsm-native.service'
    as_root bash "$repo_root/server/install-native-unit.sh" ${SSH_ACCOUNT:+"$SSH_ACCOUNT"}

    if [[ ${NO_START:-0} == 1 ]]; then
        echo 'NO_START=1: not starting the service.'
    else
        bash "$repo_root/deploy/common/start-server.sh"
    fi
    cat <<NEXT

Next steps:
  * Open TCP $NETHSM_LISTEN_PORT to the Ubuntu harness client (docs/NETWORK-HSM-SERVER-SETUP.md section 5).
  * Provision or unlock the instance and create the harness operator and key (docs/01-START-SERVERS.md).
NEXT
}
