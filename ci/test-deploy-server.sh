#!/usr/bin/env bash
# Exercise deploy/<os>/install-server.sh inside a disposable container of that
# OS: everything except the upstream build and the service start, which need
# KVM and TAP devices. A stub replaces systemctl. Never run this on a real host.
# Usage (as root, from the repository root): bash ci/test-deploy-server.sh OS_DIR
set -euo pipefail
os=${1:?usage: test-deploy-server.sh OS_DIR}
[[ -f /.dockerenv || -n ${container:-} ]] || { echo 'Refusing to run outside a container' >&2; exit 2; }

printf '#!/bin/sh\necho "[stub] systemctl $*"\n' > /usr/local/bin/systemctl
chmod +x /usr/local/bin/systemctl
id labrunner >/dev/null 2>&1 || useradd -m labrunner
run() { SKIP_BUILD=1 NO_START=1 SSH_ACCOUNT=labrunner NETHSM_REF=${NETHSM_REF:-v5.0} bash "deploy/$os/install-server.sh"; }
run

echo '--- checks'
test -x /usr/local/libexec/nethsm-native/run
test -f /etc/systemd/system/nethsm-native.service
grep -qx 'NETHSM_SRC=/opt/nethsm/src' /etc/nethsm-native/nethsm-native.env
grep -qx 'OPAMSWITCH=nethsm' /etc/nethsm-native/nethsm-native.env
grep -q '^labrunner ALL=(root) NOPASSWD: .*systemctl start nethsm-native.service$' /etc/sudoers.d/nethsm-harness
opam_as_nethsm() { runuser -u nethsm -- env HOME=/opt/nethsm OPAMROOT=/opt/nethsm/opam "$@"; }
opam_as_nethsm opam exec --switch=nethsm -- ocaml -version
runuser -u nethsm -- bash -c 'cd /opt/nethsm/src && git describe --tags'   # git 1.8 (CentOS 7) has no -C
test -x /opt/nethsm/src/tools/setup-net-dev.sh
echo '--- wrong OS is refused'
for other in ubuntu-22.04 rockylinux-8 centos-7; do
    [[ $other == "$os" ]] && continue
    if bash "deploy/$other/install-server.sh" >/dev/null 2>&1; then echo "deploy/$other ran on $os" >&2; exit 1; fi
done
echo '--- rerun is idempotent'
run > /dev/null
echo "PASS: deploy/$os/install-server.sh"
