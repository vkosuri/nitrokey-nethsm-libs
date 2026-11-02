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
python3 -I - "${SSH_TARGET#*@}" "$NETHSM_PORT" "$config" <<'PY'
import hashlib
import http.client
import json
import os
from pathlib import Path
import ssl
import sys
import time

host, port, directory = sys.argv[1:]
port = int(port)
if not 1 <= port <= 65535:
    sys.exit("Invalid NetHSM port")
config = Path(directory)
pinned = (config / "certificate-sha256").read_text().strip()
want = pinned.replace(":", "").lower()
if len(want) != 64 or any(c not in "0123456789abcdef" for c in want):
    sys.exit(f"{config}/certificate-sha256 is not a SHA-256 fingerprint")
slot = {
    "label": (config / "token-label").read_text().strip(),
    "operator": {"username": (config / "operator-user").read_text().strip()},
    "instances": [{
        "url": f"https://{host}:{port}/api/v1",
        "sha256_fingerprints": [pinned],
    }],
}
with open(os.environ["P11NETHSM_CONFIG_FILE"], "w") as out:
    json.dump({"slots": [slot]}, out)

# Wait for the API to report Operational. A listening port is not enough:
# a Locked or Unprovisioned instance accepts connections but cannot sign.
# The certificate is authenticated by the pinned fingerprint, not a CA.
context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
context.check_hostname = False
context.verify_mode = ssl.CERT_NONE
guidance = {
    "Locked": "unlock it with the lab's unlock passphrase (nitropy nethsm unlock)",
    "Unprovisioned": "provision it and create the harness operator and key (docs/01-START-SERVERS.md)",
}
deadline = time.monotonic() + int(os.environ.get("NETHSM_READY_TIMEOUT", "120"))
last = "no response"
while True:
    conn = http.client.HTTPSConnection(host, port, context=context, timeout=5)
    try:
        conn.connect()
        got = hashlib.sha256(conn.sock.getpeercert(binary_form=True)).hexdigest()
        if got != want:
            sys.exit(f"{host}:{port} presented certificate SHA-256 {got}, "
                     f"expected {want} from {config}/certificate-sha256")
        conn.request("GET", "/api/v1/health/state", headers={"Accept": "application/json"})
        response = conn.getresponse()
        body = response.read()
        if response.status != 200:
            raise ValueError(f"HTTP {response.status}")
        state = json.loads(body)["state"]
        if state == "Operational":
            print(f"{host}:{port} is Operational (pinned certificate matched)", flush=True)
            break
        if state in guidance:
            sys.exit(f"{host}:{port} reports {state}: {guidance[state]}")
        last = f"state {state}"
    except (OSError, http.client.HTTPException, ValueError, KeyError) as error:
        last = f"{type(error).__name__}: {error}"
    finally:
        conn.close()
    if time.monotonic() >= deadline:
        sys.exit(f"{host}:{port} did not become Operational ({last})")
    time.sleep(2)
PY
libs=(harness-lib/*.so)
[[ ${#libs[@]} == 1 && -s ${libs[0]} ]]
bash ci/test-remote-nethsm.sh "${libs[0]}" "$config"
