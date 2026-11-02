#!/usr/bin/env bash
# ExecStart of nethsm-native.service, running as root. It prepares the
# upstream development network, exposes the instance's HTTPS API on a
# client-reachable port, then runs the upstream development system.
set -euo pipefail
: "${NETHSM_SRC:?set NETHSM_SRC in /etc/nethsm-native/nethsm-native.env}"
run_user=${NETHSM_RUN_USER:-root}
run_cmd=${NETHSM_RUN_CMD:-make run}
listen=${NETHSM_LISTEN_PORT:-8443}
upstream=${NETHSM_UPSTREAM:-192.168.1.1:443}
[[ -d $NETHSM_SRC && -f $NETHSM_SRC/Makefile ]] || {
    echo "NETHSM_SRC=$NETHSM_SRC is not a built Nitrokey/nethsm checkout" >&2; exit 1; }
cd "$NETHSM_SRC"

if [[ ${NETHSM_SETUP_NET:-1} == 1 ]]; then
    tools/setup-net-dev.sh
fi

# TCP pass-through keeps the instance's own TLS certificate, so the
# client's pinned SHA-256 fingerprint still authenticates the server.
if [[ $listen != 0 ]]; then
    command -v socat >/dev/null || { echo 'socat is required for NETHSM_LISTEN_PORT' >&2; exit 1; }
    socat "TCP-LISTEN:$listen,fork,reuseaddr" "TCP:$upstream" &
    echo "Forwarding 0.0.0.0:$listen to $upstream (pid $!)"
fi

# systemd stops every process in the unit's cgroup, including socat.
script="eval \"\$(opam env)\" && exec $run_cmd"
if [[ $run_user == root ]]; then
    exec bash -c "$script"
fi
exec runuser -u "$run_user" -- bash -c "$script"
