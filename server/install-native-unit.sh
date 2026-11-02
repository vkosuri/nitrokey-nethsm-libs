#!/usr/bin/env bash
# Install nethsm-native.service on a lab server. Run as root from the
# repository root:  bash server/install-native-unit.sh [SSH_ACCOUNT]
# SSH_ACCOUNT is the harness login allowed to start only this unit via sudo.
set -euo pipefail
(( EUID == 0 )) || { echo 'Run as root' >&2; exit 1; }
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ssh_account=${1:-}

install -D -m 0755 "$here/nethsm-native-run.sh" /usr/local/libexec/nethsm-native/run
install -D -m 0644 "$here/nethsm-native.service" /etc/systemd/system/nethsm-native.service
install -d -m 0755 /etc/nethsm-native
if [[ ! -e /etc/nethsm-native/nethsm-native.env ]]; then
    install -m 0644 "$here/nethsm-native.env.example" /etc/nethsm-native/nethsm-native.env
    echo 'Created /etc/nethsm-native/nethsm-native.env; edit NETHSM_SRC and the run account.'
fi

if [[ -n $ssh_account ]]; then
    id "$ssh_account" >/dev/null
    systemctl=$(command -v systemctl)
    rule=$(mktemp)
    trap 'rm -f "$rule"' EXIT
    printf '%s ALL=(root) NOPASSWD: %s start nethsm-native.service\n' "$ssh_account" "$systemctl" > "$rule"
    visudo -cf "$rule"
    install -m 0440 "$rule" /etc/sudoers.d/nethsm-harness
    echo "Allowed $ssh_account to run: sudo -n $systemctl start nethsm-native.service"
fi

command -v socat >/dev/null || echo 'Warning: install socat, or set NETHSM_LISTEN_PORT=0.' >&2
systemctl daemon-reload
echo 'Installed. Stop any foreground `make run`, then: systemctl start nethsm-native.service'
