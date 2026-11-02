#!/usr/bin/env bash
# Start nethsm-native.service and report the API state from this host.
# Usage: start-server.sh [--restart]. Exit status: 0 once the API answers.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
envfile=/etc/nethsm-native/nethsm-native.env
[[ -r $envfile ]] || die "$envfile missing; run deploy/<os>/install-server.sh first"
port=$(sed -n 's/^NETHSM_LISTEN_PORT=//p' "$envfile")
endpoint=127.0.0.1:${port:-8443}
if [[ $port == 0 ]]; then  # no forward: ask the instance directly
    endpoint=$(sed -n 's/^NETHSM_UPSTREAM=//p' "$envfile"); endpoint=${endpoint:-192.168.1.1:443}
fi

action=start; [[ ${1:-} == --restart ]] && action=restart
log "systemctl $action nethsm-native.service"
as_root systemctl "$action" nethsm-native.service
systemctl is-active --quiet nethsm-native.service || {
    as_root journalctl -u nethsm-native.service -n 40 --no-pager >&2 || true
    die 'nethsm-native.service is not active'
}

# Local check only: the Ubuntu client authenticates the server by its pinned
# certificate fingerprint, so certificate verification is skipped here.
log "Waiting for https://$endpoint/api/v1/health/state"
state=
for ((i = 0; i < ${NETHSM_READY_TIMEOUT:-120}; i += 2)); do
    if body=$(curl -ksS --max-time 3 "https://$endpoint/api/v1/health/state" 2>/dev/null); then
        state=$(sed -n 's/.*"state" *: *"\([A-Za-z]*\)".*/\1/p' <<<"$body")
        [[ -n $state ]] && break
    fi
    sleep 2
done
case $state in
    Operational) echo 'NetHSM is Operational. The harness can test this server.' ;;
    Locked) echo 'NetHSM is Locked: unlock it (nitropy nethsm --host HOST:PORT unlock) before testing.' ;;
    Unprovisioned) echo 'NetHSM is Unprovisioned: provision it and create the harness operator and key (docs/01-START-SERVERS.md).' ;;
    '') as_root journalctl -u nethsm-native.service -n 40 --no-pager >&2 || true
        die "no answer from $endpoint within ${NETHSM_READY_TIMEOUT:-120}s" ;;
    *) echo "NetHSM reports state $state." ;;
esac
