#!/usr/bin/env bash
# Build the upstream NetHSM development system on Rocky Linux 8 and run it as
# nethsm-native.service for the PKCS#11 harness lab.
#
# Usage: sudo [VAR=value ...] bash deploy/rockylinux-8/install-server.sh
#
#   NETHSM_REF=<tag|commit>  upstream revision; use the same one on all servers (default: main)
#   SSH_ACCOUNT=<user>       harness SSH login allowed to start the unit via sudo
#   NETHSM_LISTEN_PORT=8443  client-reachable HTTPS port (GitHub environment NETHSM_PORT)
#   NETHSM_BUILD_CMD=...     upstream build command (default: make -j$(nproc) build)
#   NETHSM_OCAML=4.14.4      OCaml version for the OPAM switch (upstream's documented version)
#   SKIP_BUILD=1 / NO_START=1  skip the upstream build / do not start the service
# See deploy/README.md for every setting. Safe to rerun.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/../common/lib.sh"
. "$here/../common/server.sh"
show_help "$@"
require_os rocky 8

log 'Installing build and runtime packages'
as_root dnf -y install gcc gcc-c++ make m4 pkgconf-pkg-config git curl rsync patch \
    unzip bzip2 gmp-devel socat iproute tar sudo util-linux git-daemon
install_server
