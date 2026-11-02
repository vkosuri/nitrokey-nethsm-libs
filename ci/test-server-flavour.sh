#!/usr/bin/env bash
set -euo pipefail
. /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 22.04 && $(uname -m) == x86_64 ]]
case "$SERVER_OS" in centos-7|rockylinux-8|ubuntu-22.04) ;; *) exit 2 ;; esac
[[ $SSH_TARGET =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*@[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]]
umask 077
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf '%s\n' "${SSH_KEY:?}" > "$tmp/key"
printf '%s\n' "${SSH_KNOWN_HOSTS:?}" > "$tmp/hosts"
unset SSH_KEY SSH_KNOWN_HOSTS
ssh -T -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$tmp/hosts" \
    -i "$tmp/key" "$SSH_TARGET" bash -s -- "$SERVER_OS" <<'REMOTE'
set -eu
. /etc/os-release
case "$1:$ID:$VERSION_ID" in
    centos-7:centos:7|centos-7:centos:7.*|rockylinux-8:rocky:8|rockylinux-8:rocky:8.*|ubuntu-22.04:ubuntu:22.04) ;;
    *) echo "Expected $1, found $ID $VERSION_ID" >&2; exit 2 ;;
esac
sudo -n systemctl start nethsm-native.service
systemctl is-active --quiet nethsm-native.service
echo "NetHSM service active on $(hostname) ($ID $VERSION_ID)"
REMOTE

# Use the same hostname for service startup and the PKCS#11 module endpoint.
config="/etc/nethsm-harness/$SERVER_OS"
export P11NETHSM_CONFIG_FILE="$tmp/module.conf"
python3 - "${SSH_TARGET#*@}" "$NETHSM_PORT" "$config" <<'PY'
import json
import os
from pathlib import Path
import socket
import sys
import time

host, port, directory = sys.argv[1:]
port = int(port)
if not 1 <= port <= 65535:
    sys.exit("Invalid NetHSM port")
config = Path(directory)
slot = {
    "label": (config / "token-label").read_text().strip(),
    "operator": {"username": (config / "operator-user").read_text().strip()},
    "instances": [{
        "url": f"https://{host}:{port}/api/v1",
        "sha256_fingerprints": [(config / "certificate-sha256").read_text().strip()],
    }],
}
with open(os.environ["P11NETHSM_CONFIG_FILE"], "w") as out:
    json.dump({"slots": [slot]}, out)
for attempt in range(20):
    try:
        with socket.create_connection((host, port), timeout=2):
            break
    except OSError:
        if attempt == 19:
            raise
        time.sleep(1)
print(f"Connected from Ubuntu client to {host}:{port}", flush=True)
PY
libs=(harness-lib/*.so)
[[ ${#libs[@]} == 1 && -s ${libs[0]} ]]
bash ci/test-remote-nethsm.sh "${libs[0]}" "$config"
